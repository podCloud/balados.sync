defmodule BaladosSyncCore.SyncResolver do
  @moduledoc """
  Multi-device sync conflict resolution strategies.

  ## Resolution Strategies by Entity Type

  - **Subscriptions**: Last-Write-Wins (LWW)
  - **Play positions**: Highest-Progress-Wins (furthest position wins)
  - **Playlists**: Three-way merge (add/remove operations merged, LWW for metadata)
  - **Privacy settings**: Last-Write-Wins

  ## Conflict Detection

  A conflict is detected when:
  1. Both local and remote have been modified since last sync
  2. The modifications are different

  ## Conflict Response

  Each resolution returns both the winning value and conflict metadata for client awareness.
  """

  @type resolution :: :local_wins | :remote_wins | :merged | :no_conflict
  @type conflict_info :: %{
          type: atom(),
          local: map(),
          remote: map(),
          resolution: resolution(),
          reason: String.t()
        }

  @doc """
  Resolve a subscription conflict.

  Strategy: Last-Write-Wins based on the most recent of subscribed_at/unsubscribed_at.

  ## Examples

      iex> local = %{subscribed_at: ~U[2024-01-20 10:00:00Z], unsubscribed_at: nil}
      iex> remote = %{subscribed_at: ~U[2024-01-19 10:00:00Z], unsubscribed_at: nil}
      iex> SyncResolver.resolve_subscription(local, remote)
      {:ok, %{subscribed_at: ~U[2024-01-20 10:00:00Z], ...}, :local_wins, nil}
  """
  @spec resolve_subscription(map(), map()) ::
          {:ok, map(), resolution(), conflict_info() | nil}
  def resolve_subscription(local, remote) do
    local_time = effective_subscription_time(local)
    remote_time = effective_subscription_time(remote)

    case DateTime.compare(local_time, remote_time) do
      :gt ->
        {:ok, local, :local_wins, nil}

      :lt ->
        {:ok, remote, :remote_wins, nil}

      :eq ->
        # Tie-breaker: prefer subscribed over unsubscribed
        winner = prefer_subscribed(local, remote)
        {:ok, winner, :merged, nil}
    end
  end

  @doc """
  Resolve a play position conflict.

  Strategy: Highest-Progress-Wins - the furthest position is likely where the user actually is.
  Exception: If local has a `reset` flag, use local regardless of position.

  ## Examples

      iex> local = %{position: 1500, played: false}
      iex> remote = %{position: 2000, played: false}
      iex> SyncResolver.resolve_play_position(local, remote)
      {:ok, %{position: 2000, ...}, :remote_wins, conflict_info}
  """
  @spec resolve_play_position(map(), map()) ::
          {:ok, map(), resolution(), conflict_info() | nil}
  def resolve_play_position(local, remote) do
    # Handle reset flag - user explicitly started over
    if Map.get(local, :reset, false) do
      {:ok, local, :local_wins, build_conflict_info(:play_position, local, remote, :local_wins, "Local reset flag")}
    else
      local_position = local[:position] || 0
      remote_position = remote[:position] || 0

      # If one is marked as played, it wins (episode completed)
      cond do
        local[:played] && !remote[:played] ->
          {:ok, local, :local_wins, build_conflict_info(:play_position, local, remote, :local_wins, "Local marked as played")}

        remote[:played] && !local[:played] ->
          {:ok, remote, :remote_wins, build_conflict_info(:play_position, local, remote, :remote_wins, "Remote marked as played")}

        local_position > remote_position ->
          {:ok, local, :local_wins, build_conflict_info(:play_position, local, remote, :local_wins, "Higher local position")}

        remote_position > local_position ->
          {:ok, remote, :remote_wins, build_conflict_info(:play_position, local, remote, :remote_wins, "Higher remote position")}

        true ->
          # Same position - prefer more recent timestamp
          if newer?(local, remote) do
            {:ok, local, :local_wins, nil}
          else
            {:ok, remote, :remote_wins, nil}
          end
      end
    end
  end

  @doc """
  Resolve a playlist conflict.

  Strategy: Three-way merge
  - Metadata (name, description, is_public): Last-Write-Wins
  - Items: Union of both item sets, with position conflicts resolved by timestamp

  ## Examples

      iex> local = %{name: "My Playlist", items: [item1, item2]}
      iex> remote = %{name: "Updated Playlist", items: [item1, item3]}
      iex> SyncResolver.resolve_playlist(local, remote, base)
      {:ok, %{name: "Updated Playlist", items: [item1, item2, item3]}, :merged, nil}
  """
  @spec resolve_playlist(map(), map(), map() | nil) ::
          {:ok, map(), resolution(), conflict_info() | nil}
  def resolve_playlist(local, remote, base \\ nil) do
    # Metadata: LWW
    metadata_winner = if newer?(local, remote), do: local, else: remote

    # Items: Three-way merge
    merged_items = merge_playlist_items(
      local[:items] || [],
      remote[:items] || [],
      if(base, do: base[:items] || [], else: [])
    )

    merged = %{
      name: metadata_winner[:name],
      description: metadata_winner[:description],
      is_public: metadata_winner[:is_public],
      items: merged_items,
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    # If items changed in both, it's a merge
    local_items_set = MapSet.new(local[:items] || [], &item_key/1)
    remote_items_set = MapSet.new(remote[:items] || [], &item_key/1)

    resolution = if MapSet.equal?(local_items_set, remote_items_set) do
      if newer?(local, remote), do: :local_wins, else: :remote_wins
    else
      :merged
    end

    {:ok, merged, resolution, nil}
  end

  @doc """
  Resolve a privacy setting conflict.

  Strategy: Last-Write-Wins - most recent privacy choice wins.
  """
  @spec resolve_privacy(map(), map()) :: {:ok, map(), resolution(), conflict_info() | nil}
  def resolve_privacy(local, remote) do
    if newer?(local, remote) do
      {:ok, local, :local_wins, nil}
    else
      {:ok, remote, :remote_wins, nil}
    end
  end

  @doc """
  Batch resolve conflicts for a sync operation.

  Takes maps of local and remote data, returns resolved data with conflict info.
  """
  @spec resolve_sync(map(), map()) :: {:ok, map(), [conflict_info()]}
  def resolve_sync(local_data, remote_data) do
    conflicts = []

    # Resolve subscriptions
    {resolved_subs, sub_conflicts} = resolve_map(
      local_data[:subscriptions] || %{},
      remote_data[:subscriptions] || %{},
      &resolve_subscription/2
    )
    conflicts = conflicts ++ sub_conflicts

    # Resolve play statuses
    {resolved_plays, play_conflicts} = resolve_map(
      local_data[:play_statuses] || %{},
      remote_data[:play_statuses] || %{},
      &resolve_play_position/2
    )
    conflicts = conflicts ++ play_conflicts

    # Resolve playlists
    {resolved_playlists, playlist_conflicts} = resolve_map(
      local_data[:playlists] || %{},
      remote_data[:playlists] || %{},
      fn local, remote -> resolve_playlist(local, remote, nil) end
    )
    conflicts = conflicts ++ playlist_conflicts

    resolved = %{
      subscriptions: resolved_subs,
      play_statuses: resolved_plays,
      playlists: resolved_playlists
    }

    {:ok, resolved, Enum.filter(conflicts, & &1)}
  end

  # Private helpers

  defp effective_subscription_time(%{subscribed_at: sub_at, unsubscribed_at: unsub_at}) do
    case {sub_at, unsub_at} do
      {nil, nil} -> ~U[1970-01-01 00:00:00Z]
      {sub, nil} -> sub
      {nil, unsub} -> unsub
      {sub, unsub} -> if DateTime.compare(sub, unsub) == :gt, do: sub, else: unsub
    end
  end

  defp effective_subscription_time(_), do: ~U[1970-01-01 00:00:00Z]

  defp prefer_subscribed(local, remote) do
    cond do
      local[:unsubscribed_at] == nil && remote[:unsubscribed_at] != nil -> local
      remote[:unsubscribed_at] == nil && local[:unsubscribed_at] != nil -> remote
      true -> local
    end
  end

  defp newer?(local, remote) do
    local_time = local[:updated_at] || ~U[1970-01-01 00:00:00Z]
    remote_time = remote[:updated_at] || ~U[1970-01-01 00:00:00Z]
    DateTime.compare(local_time, remote_time) != :lt
  end

  defp build_conflict_info(type, local, remote, resolution, reason) do
    %{
      type: type,
      local: local,
      remote: remote,
      resolution: resolution,
      reason: reason
    }
  end

  defp merge_playlist_items(local_items, remote_items, base_items) do
    # Create sets of item keys
    local_set = MapSet.new(local_items, &item_key/1)
    remote_set = MapSet.new(remote_items, &item_key/1)
    base_set = MapSet.new(base_items, &item_key/1)

    # Items added locally (in local but not in base)
    local_additions = MapSet.difference(local_set, base_set)

    # Items added remotely (in remote but not in base)
    remote_additions = MapSet.difference(remote_set, base_set)

    # Items removed locally (in base but not in local)
    local_removals = MapSet.difference(base_set, local_set)

    # Items removed remotely (in base but not in remote)
    remote_removals = MapSet.difference(base_set, remote_set)

    # Start with base, apply all changes
    result_set = base_set
                 |> MapSet.union(local_additions)
                 |> MapSet.union(remote_additions)
                 |> MapSet.difference(local_removals)
                 |> MapSet.difference(remote_removals)

    # Build item map for lookups
    all_items = (local_items ++ remote_items ++ base_items)
                |> Enum.uniq_by(&item_key/1)
                |> Enum.into(%{}, fn item -> {item_key(item), item} end)

    # Convert back to list with proper ordering
    result_set
    |> Enum.map(fn key -> Map.get(all_items, key) end)
    |> Enum.filter(& &1)
    |> Enum.sort_by(& &1[:position])
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} -> Map.put(item, :position, idx) end)
  end

  defp item_key(item) when is_map(item) do
    {item[:rss_source_feed] || item["rss_source_feed"],
     item[:rss_source_item] || item["rss_source_item"]}
  end

  defp item_key(_), do: nil

  defp resolve_map(local_map, remote_map, resolver_fn) do
    all_keys = MapSet.union(
      MapSet.new(Map.keys(local_map)),
      MapSet.new(Map.keys(remote_map))
    )

    Enum.reduce(all_keys, {%{}, []}, fn key, {acc_map, acc_conflicts} ->
      local = Map.get(local_map, key)
      remote = Map.get(remote_map, key)

      case {local, remote} do
        {nil, remote_val} ->
          {Map.put(acc_map, key, remote_val), acc_conflicts}

        {local_val, nil} ->
          {Map.put(acc_map, key, local_val), acc_conflicts}

        {local_val, remote_val} ->
          {:ok, resolved, _resolution, conflict} = resolver_fn.(local_val, remote_val)
          new_conflicts = if conflict, do: [conflict | acc_conflicts], else: acc_conflicts
          {Map.put(acc_map, key, resolved), new_conflicts}
      end
    end)
  end
end
