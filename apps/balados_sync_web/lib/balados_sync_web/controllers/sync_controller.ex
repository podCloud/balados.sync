defmodule BaladosSyncWeb.SyncController do
  @moduledoc """
  Full state synchronization controller for multi-device sync.

  ## Conflict Resolution Strategy

  - **Subscriptions**: Last-Write-Wins (LWW)
  - **Play positions**: Highest-Progress-Wins (furthest position wins)
  - **Playlists**: Three-way merge (items merged, metadata LWW)

  Conflicts are reported in the response for client awareness.
  """
  use BaladosSyncWeb, :controller

  import Ecto.Query
  alias Ecto.Multi
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Subscription, PlayStatus, Playlist, PlaylistItem}
  alias BaladosSyncCore.SyncResolver
  alias BaladosSyncWeb.Plugs.JWTAuth
  alias BaladosSyncWeb.Plugs.RateLimiter

  require Logger

  # Scope requirements for sync - requires user.sync or full user access
  plug JWTAuth, [scopes_any: ["user.sync", "user"]] when action in [:sync]

  # Rate limit: 30 requests per minute (write operation)
  plug RateLimiter, limit: 30, window_ms: 60_000, key: :user_id, namespace: "sync"

  @doc """
  Sync endpoint - accepts local changes and returns merged state with conflicts.

  ## Request Format

  ```json
  {
    "last_sync": "2024-01-19T10:00:00Z",
    "changes": {
      "subscriptions": [...],
      "plays": [...],
      "playlists": [...]
    }
  }
  ```

  ## Response Format

  ```json
  {
    "sync_token": "2024-01-20T10:35:00Z",
    "changes": {...},
    "conflicts": [...]
  }
  ```
  """
  def sync(conn, params) do
    user_id = conn.assigns.current_user_id
    last_sync = parse_datetime(params["last_sync"])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Parse incoming client changes
    client_changes = params["changes"] || %{}
    subscriptions = parse_subscriptions(client_changes["subscriptions"] || [])
    play_statuses = parse_play_statuses(client_changes["plays"] || client_changes["play_statuses"] || [])
    playlists = parse_playlists(client_changes["playlists"] || [])

    # Get server state for conflict detection
    server_data = %{
      subscriptions: get_server_subscriptions(user_id),
      play_statuses: get_server_play_statuses(user_id),
      playlists: get_server_playlists(user_id)
    }

    client_data = %{
      subscriptions: subscriptions,
      play_statuses: play_statuses,
      playlists: playlists
    }

    # Build multi transaction with conflict resolution
    {multi, conflicts} = build_sync_multi(user_id, client_data, server_data, now)

    case ProjectionsRepo.transaction(multi) do
      {:ok, _} ->
        # Get changes since last_sync for the client
        remote_changes = get_changes_since(user_id, last_sync)

        response = %{
          sync_token: DateTime.to_iso8601(now),
          changes: remote_changes,
          conflicts: format_conflicts(conflicts)
        }

        Logger.info("Sync completed for user #{user_id}: #{length(conflicts)} conflicts resolved")
        json(conn, response)

      {:error, _operation, reason, _changes} ->
        Logger.error("Sync failed for user #{user_id}: #{inspect(reason)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Sync failed", code: "SYNC_ERROR", details: inspect(reason)})
    end
  end

  # Build the sync transaction with conflict resolution
  defp build_sync_multi(user_id, client_data, server_data, now) do
    multi = Multi.new()

    # Sync subscriptions with LWW
    {multi, sub_conflicts} = sync_subscriptions_with_resolution(
      multi, user_id, client_data.subscriptions, server_data.subscriptions, now
    )

    # Sync play statuses with Highest-Progress-Wins
    {multi, play_conflicts} = sync_play_statuses_with_resolution(
      multi, user_id, client_data.play_statuses, server_data.play_statuses, now
    )

    # Sync playlists with three-way merge
    {multi, playlist_conflicts} = sync_playlists_with_resolution(
      multi, user_id, client_data.playlists, server_data.playlists, now
    )

    all_conflicts = (sub_conflicts ++ play_conflicts ++ playlist_conflicts)
                    |> Enum.filter(& &1)

    {multi, all_conflicts}
  end

  # Sync subscriptions with LWW conflict resolution
  defp sync_subscriptions_with_resolution(multi, _user_id, subs, _server_subs, _now) when map_size(subs) == 0 do
    {multi, []}
  end

  defp sync_subscriptions_with_resolution(multi, user_id, subs, server_subs, now) do
    Enum.reduce(subs, {multi, []}, fn {feed, client_sub}, {acc_multi, acc_conflicts} ->
      server_sub = Map.get(server_subs, feed)

      if is_nil(server_sub) do
        # No server version - just insert
        attrs = build_subscription_attrs(user_id, feed, client_sub, now)
        new_multi = Multi.insert(
          acc_multi,
          {:subscription, feed},
          Subscription.changeset(%Subscription{}, attrs),
          on_conflict: {:replace, [:rss_source_id, :subscribed_at, :unsubscribed_at, :updated_at]},
          conflict_target: [:user_id, :rss_source_feed]
        )
        {new_multi, acc_conflicts}
      else
        # Conflict resolution using SyncResolver
        client_map = %{
          subscribed_at: client_sub.subscribed_at,
          unsubscribed_at: client_sub.unsubscribed_at,
          updated_at: get_effective_updated_at(client_sub)
        }
        server_map = %{
          subscribed_at: server_sub.subscribed_at,
          unsubscribed_at: server_sub.unsubscribed_at,
          updated_at: server_sub.updated_at
        }

        {:ok, _winner, resolution, conflict_info} = SyncResolver.resolve_subscription(client_map, server_map)

        if resolution in [:local_wins, :merged] do
          attrs = build_subscription_attrs(user_id, feed, client_sub, now)
          new_multi = Multi.insert(
            acc_multi,
            {:subscription, feed},
            Subscription.changeset(%Subscription{}, attrs),
            on_conflict: {:replace, [:rss_source_id, :subscribed_at, :unsubscribed_at, :updated_at]},
            conflict_target: [:user_id, :rss_source_feed]
          )
          {new_multi, maybe_add_conflict(acc_conflicts, conflict_info)}
        else
          {acc_multi, maybe_add_conflict(acc_conflicts, conflict_info)}
        end
      end
    end)
  end

  defp build_subscription_attrs(user_id, feed, sub, now) do
    %{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_id: sub.rss_source_id,
      subscribed_at: sub.subscribed_at,
      unsubscribed_at: sub.unsubscribed_at,
      updated_at: now
    }
  end

  # Sync play statuses with Highest-Progress-Wins
  defp sync_play_statuses_with_resolution(multi, _user_id, statuses, _server_statuses, _now) when map_size(statuses) == 0 do
    {multi, []}
  end

  defp sync_play_statuses_with_resolution(multi, user_id, statuses, server_statuses, now) do
    Enum.reduce(statuses, {multi, []}, fn {item, client_status}, {acc_multi, acc_conflicts} ->
      server_status = Map.get(server_statuses, item)

      if is_nil(server_status) do
        # No server version - just insert
        attrs = build_play_status_attrs(user_id, item, client_status, now)
        new_multi = Multi.insert(
          acc_multi,
          {:play_status, item},
          PlayStatus.changeset(%PlayStatus{}, attrs),
          on_conflict: {:replace, [:rss_source_feed, :position, :played, :updated_at]},
          conflict_target: [:user_id, :rss_source_item]
        )
        {new_multi, acc_conflicts}
      else
        # Conflict resolution using Highest-Progress-Wins
        client_map = %{
          position: client_status.position || 0,
          played: client_status.played || false,
          updated_at: client_status.updated_at,
          reset: Map.get(client_status, :reset, false)
        }
        server_map = %{
          position: server_status.position || 0,
          played: server_status.played || false,
          updated_at: server_status.updated_at
        }

        {:ok, winner, resolution, conflict_info} = SyncResolver.resolve_play_position(client_map, server_map)

        if resolution == :local_wins do
          merged_status = Map.merge(client_status, %{
            position: winner.position,
            played: winner.played
          })
          attrs = build_play_status_attrs(user_id, item, merged_status, now)
          new_multi = Multi.insert(
            acc_multi,
            {:play_status, item},
            PlayStatus.changeset(%PlayStatus{}, attrs),
            on_conflict: {:replace, [:rss_source_feed, :position, :played, :updated_at]},
            conflict_target: [:user_id, :rss_source_item]
          )
          {new_multi, maybe_add_conflict(acc_conflicts, conflict_info)}
        else
          {acc_multi, maybe_add_conflict(acc_conflicts, conflict_info)}
        end
      end
    end)
  end

  defp build_play_status_attrs(user_id, item, status, now) do
    %{
      user_id: user_id,
      rss_source_feed: status.rss_source_feed,
      rss_source_item: item,
      position: status.position || 0,
      played: status.played || false,
      updated_at: now
    }
  end

  # Sync playlists with resolution
  defp sync_playlists_with_resolution(multi, _user_id, playlists, _server_playlists, _now) when map_size(playlists) == 0 do
    {multi, []}
  end

  defp sync_playlists_with_resolution(multi, user_id, playlists, server_playlists, now) do
    Enum.reduce(playlists, {multi, []}, fn {playlist_id, client_playlist}, {acc_multi, acc_conflicts} ->
      server_playlist = Map.get(server_playlists, playlist_id)
      client_updated_at = client_playlist.updated_at || now

      should_update =
        is_nil(server_playlist) or
          DateTime.compare(client_updated_at, server_playlist.updated_at || ~U[1970-01-01 00:00:00Z]) == :gt

      if should_update do
        if client_playlist.deleted_at do
          # Soft delete playlist and items
          new_multi = acc_multi
          |> Multi.update_all(
            {:delete_playlist, playlist_id},
            from(p in Playlist, where: p.id == ^playlist_id and p.user_id == ^user_id),
            set: [deleted_at: client_playlist.deleted_at, updated_at: now]
          )
          |> Multi.update_all(
            {:delete_playlist_items, playlist_id},
            from(pi in PlaylistItem, where: pi.playlist_id == ^playlist_id and pi.user_id == ^user_id),
            set: [deleted_at: client_playlist.deleted_at, updated_at: now]
          )
          {new_multi, acc_conflicts}
        else
          # Upsert playlist (clear deleted_at if previously deleted)
          playlist_attrs = %{
            id: playlist_id,
            user_id: user_id,
            name: client_playlist.name,
            description: client_playlist.description,
            is_public: client_playlist.is_public || false,
            deleted_at: nil,
            updated_at: now
          }

          new_multi = Multi.insert(
            acc_multi,
            {:playlist, playlist_id},
            %Playlist{} |> Ecto.Changeset.change(playlist_attrs),
            on_conflict: {:replace, [:name, :description, :is_public, :deleted_at, :updated_at]},
            conflict_target: [:id, :user_id]
          )

          # Sync playlist items
          new_multi = sync_playlist_items(new_multi, user_id, playlist_id, client_playlist.items, now)
          {new_multi, acc_conflicts}
        end
      else
        {acc_multi, acc_conflicts}
      end
    end)
  end

  defp get_server_subscriptions(user_id) do
    from(s in Subscription, where: s.user_id == ^user_id)
    |> ProjectionsRepo.all()
    |> Enum.into(%{}, fn s -> {s.rss_source_feed, s} end)
  end

  defp get_server_play_statuses(user_id) do
    from(ps in PlayStatus, where: ps.user_id == ^user_id)
    |> ProjectionsRepo.all()
    |> Enum.into(%{}, fn ps -> {ps.rss_source_item, ps} end)
  end

  defp get_server_playlists(user_id) do
    from(p in Playlist, where: p.user_id == ^user_id)
    |> ProjectionsRepo.all()
    |> Enum.into(%{}, fn p -> {p.id, p} end)
  end

  defp sync_playlist_items(multi, _user_id, _playlist_id, items, _now) when items == [], do: multi

  defp sync_playlist_items(multi, user_id, playlist_id, items, now) do
    Enum.reduce(items, multi, fn item, acc ->
      item_attrs = %{
        user_id: user_id,
        playlist_id: playlist_id,
        rss_source_feed: item.rss_source_feed,
        rss_source_item: item.rss_source_item,
        item_title: item.item_title,
        feed_title: item.feed_title,
        position: item.position,
        updated_at: now,
        deleted_at: nil
      }

      Multi.insert(
        acc,
        {:playlist_item, playlist_id, item.rss_source_item},
        %PlaylistItem{} |> Ecto.Changeset.change(item_attrs),
        on_conflict: {:replace, [:item_title, :feed_title, :position, :updated_at, :deleted_at]},
        conflict_target: [:playlist_id, :rss_source_feed, :rss_source_item, :user_id]
      )
    end)
  end

  # Get changes since last sync
  defp get_changes_since(user_id, nil) do
    # First sync - return all data
    get_user_data(user_id)
  end

  defp get_changes_since(user_id, last_sync) do
    %{
      subscriptions: get_subscriptions_since(user_id, last_sync),
      plays: get_play_statuses_since(user_id, last_sync),
      playlists: get_playlists_since(user_id, last_sync)
    }
  end

  defp get_subscriptions_since(user_id, since) do
    from(s in Subscription,
      where: s.user_id == ^user_id and s.updated_at > ^since,
      select: %{
        rss_source_feed: s.rss_source_feed,
        rss_source_id: s.rss_source_id,
        subscribed_at: s.subscribed_at,
        unsubscribed_at: s.unsubscribed_at,
        updated_at: s.updated_at
      }
    )
    |> ProjectionsRepo.all()
  end

  defp get_play_statuses_since(user_id, since) do
    from(ps in PlayStatus,
      where: ps.user_id == ^user_id and ps.updated_at > ^since,
      select: %{
        rss_source_feed: ps.rss_source_feed,
        rss_source_item: ps.rss_source_item,
        position: ps.position,
        played: ps.played,
        updated_at: ps.updated_at
      }
    )
    |> ProjectionsRepo.all()
  end

  defp get_playlists_since(user_id, since) do
    from(p in Playlist,
      where: p.user_id == ^user_id and p.updated_at > ^since,
      left_join: pi in PlaylistItem, on: pi.playlist_id == p.id,
      preload: [items: pi],
      select: p
    )
    |> ProjectionsRepo.all()
    |> Enum.map(fn p ->
      %{
        id: p.id,
        name: p.name,
        description: p.description,
        is_public: p.is_public,
        deleted_at: p.deleted_at,
        updated_at: p.updated_at,
        items: Enum.map(p.items || [], fn i ->
          %{
            rss_source_feed: i.rss_source_feed,
            rss_source_item: i.rss_source_item,
            item_title: i.item_title,
            feed_title: i.feed_title,
            position: i.position
          }
        end)
      }
    end)
  end

  # Format conflicts for API response
  defp format_conflicts(conflicts) do
    Enum.map(conflicts, fn conflict ->
      %{
        type: to_string(conflict.type),
        local: format_conflict_data(conflict.local),
        remote: format_conflict_data(conflict.remote),
        resolution: to_string(conflict.resolution),
        reason: conflict.reason
      }
    end)
  end

  defp format_conflict_data(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {to_string(k), format_value(v)} end)
    |> Enum.into(%{})
  end

  defp format_conflict_data(data), do: data

  defp format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_value(v), do: v

  defp maybe_add_conflict(conflicts, nil), do: conflicts
  defp maybe_add_conflict(conflicts, conflict), do: [conflict | conflicts]

  # Get effective updated_at: for subscriptions, use the most recent of subscribed_at/unsubscribed_at
  defp get_effective_updated_at(%{subscribed_at: sub_at, unsubscribed_at: unsub_at}) do
    case {sub_at, unsub_at} do
      {nil, nil} -> ~U[1970-01-01 00:00:00Z]
      {sub, nil} -> sub
      {nil, unsub} -> unsub
      {sub, unsub} -> if DateTime.compare(sub, unsub) == :gt, do: sub, else: unsub
    end
  end

  defp parse_subscriptions(subs) do
    Enum.reduce(subs, %{}, fn sub, acc ->
      Map.put(acc, sub["rss_source_feed"], %{
        rss_source_id: sub["rss_source_id"],
        subscribed_at: parse_datetime(sub["subscribed_at"]),
        unsubscribed_at: parse_datetime(sub["unsubscribed_at"])
      })
    end)
  end

  defp parse_play_statuses(statuses) do
    Enum.reduce(statuses, %{}, fn status, acc ->
      Map.put(acc, status["rss_source_item"], %{
        rss_source_feed: status["rss_source_feed"],
        position: status["position"],
        played: status["played"],
        updated_at: parse_datetime(status["updated_at"]),
        reset: status["reset"] || false
      })
    end)
  end

  defp parse_playlists(playlists) when is_list(playlists) do
    Enum.reduce(playlists, %{}, fn playlist, acc ->
      playlist_id = playlist["id"]

      if is_binary(playlist_id) and playlist_id != "" do
        Map.put(acc, playlist_id, %{
          name: playlist["name"],
          description: playlist["description"],
          is_public: playlist["is_public"] || false,
          items: parse_playlist_items(playlist["items"] || []),
          updated_at: parse_datetime(playlist["updated_at"]),
          deleted_at: parse_datetime(playlist["deleted_at"])
        })
      else
        acc
      end
    end)
  end

  defp parse_playlists(_), do: %{}

  defp parse_playlist_items(items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      %{
        rss_source_feed: item["rss_source_feed"],
        rss_source_item: item["rss_source_item"],
        item_title: item["item_title"],
        feed_title: item["feed_title"],
        position: item["position"] || index
      }
    end)
    |> Enum.filter(fn item -> is_binary(item.rss_source_item) end)
  end

  defp parse_playlist_items(_), do: []

  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp get_user_data(user_id) do
    %{
      subscriptions: BaladosSyncWeb.Queries.get_user_subscriptions(user_id),
      plays: BaladosSyncWeb.Queries.get_user_play_statuses(user_id),
      playlists: BaladosSyncWeb.Queries.get_user_playlists(user_id)
    }
  end
end
