defmodule BaladosSyncWeb.SyncController do
  use BaladosSyncWeb, :controller

  import Ecto.Query
  alias Ecto.Multi
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Subscription, PlayStatus, Playlist, PlaylistItem}
  alias BaladosSyncWeb.Plugs.JWTAuth
  alias BaladosSyncWeb.Plugs.RateLimiter

  # Scope requirements for sync - requires user.sync or full user access
  plug JWTAuth, [scopes_any: ["user.sync", "user"]] when action in [:sync]

  # Rate limit: 30 requests per minute (write operation)
  plug RateLimiter, limit: 30, window_ms: 60_000, key: :user_id, namespace: "sync"

  def sync(conn, params) do
    user_id = conn.assigns.current_user_id

    subscriptions = parse_subscriptions(params["subscriptions"] || [])
    play_statuses = parse_play_statuses(params["play_statuses"] || [])
    playlists = parse_playlists(params["playlists"] || [])

    multi =
      Multi.new()
      |> sync_subscriptions(user_id, subscriptions)
      |> sync_play_statuses(user_id, play_statuses)
      |> sync_playlists(user_id, playlists)

    case ProjectionsRepo.transaction(multi) do
      {:ok, _} ->
        synced_data = get_user_data(user_id)
        json(conn, %{status: "success", data: synced_data})

      {:error, _operation, reason, _changes} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Sync failed", details: inspect(reason)})
    end
  end

  # Sync subscriptions: merge based on timestamps
  # Only update if client data is newer than server data
  defp sync_subscriptions(multi, _user_id, subs) when map_size(subs) == 0, do: multi

  defp sync_subscriptions(multi, user_id, subs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Get current server state
    server_subs = get_server_subscriptions(user_id)

    Enum.reduce(subs, multi, fn {feed, client_sub}, acc ->
      server_sub = Map.get(server_subs, feed)
      client_updated_at = get_effective_updated_at(client_sub)

      should_update =
        is_nil(server_sub) or
          DateTime.compare(client_updated_at, server_sub.updated_at || ~U[1970-01-01 00:00:00Z]) == :gt

      if should_update do
        attrs = %{
          user_id: user_id,
          rss_source_feed: feed,
          rss_source_id: client_sub.rss_source_id,
          subscribed_at: client_sub.subscribed_at,
          unsubscribed_at: client_sub.unsubscribed_at,
          updated_at: now
        }

        Multi.insert(
          acc,
          {:subscription, feed},
          Subscription.changeset(%Subscription{}, attrs),
          on_conflict: {:replace, [:rss_source_id, :subscribed_at, :unsubscribed_at, :updated_at]},
          conflict_target: [:user_id, :rss_source_feed]
        )
      else
        acc
      end
    end)
  end

  defp get_server_subscriptions(user_id) do
    from(s in Subscription, where: s.user_id == ^user_id)
    |> ProjectionsRepo.all()
    |> Enum.into(%{}, fn s -> {s.rss_source_feed, s} end)
  end

  # Sync play statuses: merge based on updated_at
  defp sync_play_statuses(multi, _user_id, statuses) when map_size(statuses) == 0, do: multi

  defp sync_play_statuses(multi, user_id, statuses) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Get current server state
    server_statuses = get_server_play_statuses(user_id)

    Enum.reduce(statuses, multi, fn {item, client_status}, acc ->
      server_status = Map.get(server_statuses, item)
      client_updated_at = client_status.updated_at || now

      should_update =
        is_nil(server_status) or
          DateTime.compare(client_updated_at, server_status.updated_at || ~U[1970-01-01 00:00:00Z]) == :gt

      if should_update do
        attrs = %{
          user_id: user_id,
          rss_source_feed: client_status.rss_source_feed,
          rss_source_item: item,
          position: client_status.position,
          played: client_status.played,
          updated_at: client_updated_at
        }

        Multi.insert(
          acc,
          {:play_status, item},
          PlayStatus.changeset(%PlayStatus{}, attrs),
          on_conflict: {:replace, [:rss_source_feed, :position, :played, :updated_at]},
          conflict_target: [:user_id, :rss_source_item]
        )
      else
        acc
      end
    end)
  end

  defp get_server_play_statuses(user_id) do
    from(ps in PlayStatus, where: ps.user_id == ^user_id)
    |> ProjectionsRepo.all()
    |> Enum.into(%{}, fn ps -> {ps.rss_source_item, ps} end)
  end

  # Sync playlists: merge based on updated_at
  defp sync_playlists(multi, _user_id, playlists) when map_size(playlists) == 0, do: multi

  defp sync_playlists(multi, user_id, playlists) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Get current server state
    server_playlists = get_server_playlists(user_id)

    Enum.reduce(playlists, multi, fn {playlist_id, client_playlist}, acc ->
      server_playlist = Map.get(server_playlists, playlist_id)
      client_updated_at = client_playlist.updated_at || now

      should_update =
        is_nil(server_playlist) or
          DateTime.compare(client_updated_at, server_playlist.updated_at || ~U[1970-01-01 00:00:00Z]) == :gt

      if should_update do
        if client_playlist.deleted_at do
          # Soft delete playlist and items
          acc
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

          acc =
            Multi.insert(
              acc,
              {:playlist, playlist_id},
              %Playlist{} |> Ecto.Changeset.change(playlist_attrs),
              on_conflict: {:replace, [:name, :description, :is_public, :deleted_at, :updated_at]},
              conflict_target: [:id, :user_id]
            )

          # Sync playlist items
          sync_playlist_items(acc, user_id, playlist_id, client_playlist.items, now)
        end
      else
        acc
      end
    end)
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
        updated_at: parse_datetime(status["updated_at"])
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
      play_statuses: BaladosSyncWeb.Queries.get_user_play_statuses(user_id),
      playlists: BaladosSyncWeb.Queries.get_user_playlists(user_id)
    }
  end
end
