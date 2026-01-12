defmodule BaladosSyncWeb.Opml.DataImporter do
  @moduledoc """
  Imports OPML data into the database with conflict resolution.

  Uses the same merge strategy as the Sync API:
  - Subscriptions: Last-Write-Wins based on dates
  - Play statuses: Merge based on updated_at, highest progress wins
  - Playlists/Collections: Merge based on updated_at
  """

  import Ecto.Query
  require Logger

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{
    Subscription,
    PlayStatus,
    Playlist,
    PlaylistItem,
    Collection,
    CollectionSubscription
  }
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, ChangePrivacy}
  alias BaladosSyncWeb.Opml.Document

  @doc """
  Import OPML data for a user with conflict resolution.

  ## Options

  - `:dry_run` - If true, don't actually import (default: false)

  ## Returns

  `{:ok, stats}` or `{:error, reason}`

  Stats include counts of imported/skipped/merged items.
  """
  def import(user_id, %Document{} = doc, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    stats = %{
      subscriptions: %{imported: 0, skipped: 0, merged: 0},
      play_statuses: %{imported: 0, skipped: 0, merged: 0},
      playlists: %{imported: 0, skipped: 0, merged: 0},
      collections: %{imported: 0, skipped: 0, merged: 0}
    }

    if dry_run do
      # Just count what would be imported
      {:ok, calculate_dry_run_stats(user_id, doc)}
    else
      do_import(user_id, doc, stats)
    end
  end

  # ===== Main Import =====

  defp do_import(user_id, doc, stats) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Import subscriptions via CQRS commands
    sub_stats = import_subscriptions(user_id, doc.subscriptions, now)

    # Import play statuses directly (no CQRS for bulk operations)
    ps_stats = import_play_statuses(user_id, doc.subscriptions, now)

    # Import playlists
    playlist_stats = import_playlists(user_id, doc.playlists, now)

    # Import collections
    collection_stats = import_collections(user_id, doc.collections, now)

    final_stats = %{
      stats |
      subscriptions: sub_stats,
      play_statuses: ps_stats,
      playlists: playlist_stats,
      collections: collection_stats
    }

    Logger.info("OPML import completed for user #{user_id}: #{inspect(final_stats)}")
    {:ok, final_stats}
  end

  # ===== Subscriptions Import =====

  defp import_subscriptions(user_id, subscriptions, now) do
    Enum.reduce(subscriptions, %{imported: 0, skipped: 0, merged: 0}, fn sub, acc ->
      case import_subscription(user_id, sub, now) do
        :imported -> %{acc | imported: acc.imported + 1}
        :skipped -> %{acc | skipped: acc.skipped + 1}
        :merged -> %{acc | merged: acc.merged + 1}
      end
    end)
  end

  defp import_subscription(user_id, sub, now) do
    return_if_nil(sub.feed_url, :skipped, fn ->
      encoded_feed = Base.url_encode64(sub.feed_url, padding: false)
      existing = get_existing_subscription(user_id, encoded_feed)

      cond do
        # No existing subscription - import
        is_nil(existing) ->
          dispatch_subscribe(user_id, sub, encoded_feed, now)
          maybe_set_privacy(user_id, encoded_feed, sub.privacy)
          :imported

        # Existing subscription - check dates for merge
        should_update_subscription?(existing, sub) ->
          # Re-subscribe if unsubscribed, or update metadata
          dispatch_subscribe(user_id, sub, encoded_feed, now)
          maybe_set_privacy(user_id, encoded_feed, sub.privacy)
          :merged

        true ->
          :skipped
      end
    end)
  end

  defp get_existing_subscription(user_id, encoded_feed) do
    from(s in Subscription,
      where: s.user_id == ^user_id and s.rss_source_feed == ^encoded_feed
    )
    |> ProjectionsRepo.one()
  end

  defp should_update_subscription?(existing, incoming) do
    # Update if incoming is newer
    incoming_date = incoming.subscribed_at || DateTime.from_unix!(0)
    existing_date = existing.subscribed_at || DateTime.from_unix!(0)

    DateTime.compare(incoming_date, existing_date) == :gt
  end

  defp dispatch_subscribe(user_id, sub, encoded_feed, _now) do
    command = %Subscribe{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_id: sub.source_id || generate_source_id(sub.feed_url),
      subscribed_at: sub.subscribed_at || DateTime.utc_now(),
      event_infos: %{
        device_id: "opml-import",
        device_name: "OPML Import"
      }
    }

    case Dispatcher.dispatch(command) do
      :ok -> :ok
      {:error, :already_subscribed} -> :ok
      {:error, reason} ->
        Logger.warning("Failed to import subscription: #{inspect(reason)}")
        :error
    end
  end

  defp maybe_set_privacy(_user_id, _encoded_feed, nil), do: :ok
  defp maybe_set_privacy(_user_id, _encoded_feed, "public"), do: :ok
  defp maybe_set_privacy(user_id, encoded_feed, privacy) do
    command = %ChangePrivacy{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      privacy: String.to_atom(privacy),
      event_infos: %{device_id: "opml-import", device_name: "OPML Import"}
    }

    Dispatcher.dispatch(command)
  end

  # ===== Play Statuses Import =====

  defp import_play_statuses(user_id, subscriptions, now) do
    # Flatten all play statuses from subscriptions
    all_play_statuses =
      subscriptions
      |> Enum.flat_map(fn sub ->
        Enum.map(sub.play_statuses || [], fn ps ->
          {sub.feed_url, ps}
        end)
      end)
      |> Enum.reject(fn {feed_url, _} -> is_nil(feed_url) end)

    Enum.reduce(all_play_statuses, %{imported: 0, skipped: 0, merged: 0}, fn {feed_url, ps}, acc ->
      case import_play_status(user_id, feed_url, ps, now) do
        :imported -> %{acc | imported: acc.imported + 1}
        :skipped -> %{acc | skipped: acc.skipped + 1}
        :merged -> %{acc | merged: acc.merged + 1}
      end
    end)
  end

  defp import_play_status(user_id, feed_url, ps, now) do
    encoded_feed = Base.url_encode64(feed_url, padding: false)
    encoded_item = encode_item(feed_url, ps.guid)

    existing = get_existing_play_status(user_id, encoded_item)

    attrs = %{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_item: encoded_item,
      position: ps.position || 0,
      played: ps.played || false,
      updated_at: now
    }

    cond do
      is_nil(existing) ->
        insert_play_status(attrs)
        :imported

      should_update_play_status?(existing, ps) ->
        # Highest progress wins
        merged_attrs = merge_play_status(existing, ps, now)
        update_play_status(existing, merged_attrs)
        :merged

      true ->
        :skipped
    end
  end

  defp get_existing_play_status(user_id, encoded_item) do
    from(ps in PlayStatus,
      where: ps.user_id == ^user_id and ps.rss_source_item == ^encoded_item
    )
    |> ProjectionsRepo.one()
  end

  defp should_update_play_status?(existing, incoming) do
    incoming_date = incoming.updated_at || DateTime.from_unix!(0)
    existing_date = existing.updated_at || DateTime.from_unix!(0)

    DateTime.compare(incoming_date, existing_date) == :gt or
      (incoming.position || 0) > (existing.position || 0)
  end

  defp merge_play_status(existing, incoming, now) do
    # Take highest position
    position = max(existing.position || 0, incoming.position || 0)
    # Played is true if either is true
    played = (existing.played || false) or (incoming.played || false)

    %{
      position: position,
      played: played,
      updated_at: now
    }
  end

  defp insert_play_status(attrs) do
    %PlayStatus{}
    |> PlayStatus.changeset(attrs)
    |> ProjectionsRepo.insert()
  end

  defp update_play_status(existing, attrs) do
    existing
    |> PlayStatus.changeset(attrs)
    |> ProjectionsRepo.update()
  end

  # ===== Playlists Import =====

  defp import_playlists(user_id, playlists, now) do
    Enum.reduce(playlists, %{imported: 0, skipped: 0, merged: 0}, fn playlist, acc ->
      case import_playlist(user_id, playlist, now) do
        :imported -> %{acc | imported: acc.imported + 1}
        :skipped -> %{acc | skipped: acc.skipped + 1}
        :merged -> %{acc | merged: acc.merged + 1}
      end
    end)
  end

  defp import_playlist(user_id, playlist, now) do
    # Try to find existing by ID or name
    existing = get_existing_playlist(user_id, playlist)

    cond do
      is_nil(existing) ->
        create_playlist(user_id, playlist, now)
        :imported

      should_update_playlist?(existing, playlist) ->
        update_playlist(existing, playlist, now)
        :merged

      true ->
        :skipped
    end
  end

  defp get_existing_playlist(user_id, playlist) do
    query =
      if playlist.id do
        from(p in Playlist,
          where: p.user_id == ^user_id and p.id == ^playlist.id and is_nil(p.deleted_at)
        )
      else
        from(p in Playlist,
          where: p.user_id == ^user_id and p.name == ^playlist.name and is_nil(p.deleted_at)
        )
      end

    ProjectionsRepo.one(query)
  end

  defp should_update_playlist?(existing, incoming) do
    incoming_date = incoming.updated_at || DateTime.from_unix!(0)
    existing_date = existing.updated_at || DateTime.from_unix!(0)

    DateTime.compare(incoming_date, existing_date) == :gt
  end

  defp create_playlist(user_id, playlist, now) do
    playlist_id = playlist.id || Ecto.UUID.generate()

    attrs = %{
      id: playlist_id,
      user_id: user_id,
      name: playlist.name,
      description: playlist.description,
      type: playlist.type || "playlist",
      is_public: playlist.is_public || false,
      inserted_at: now,
      updated_at: now
    }

    case ProjectionsRepo.insert(%Playlist{} |> Ecto.Changeset.change(attrs)) do
      {:ok, created} ->
        import_playlist_items(user_id, created.id, playlist.items, now)
      {:error, _} ->
        :error
    end
  end

  defp update_playlist(existing, playlist, now) do
    attrs = %{
      name: playlist.name || existing.name,
      description: playlist.description || existing.description,
      type: playlist.type || existing.type,
      is_public: playlist.is_public,
      updated_at: now
    }

    existing
    |> Ecto.Changeset.change(attrs)
    |> ProjectionsRepo.update()

    # Merge items
    import_playlist_items(existing.user_id, existing.id, playlist.items, now)
  end

  defp import_playlist_items(_user_id, _playlist_id, [], _now), do: :ok
  defp import_playlist_items(user_id, playlist_id, items, now) do
    Enum.each(items, fn item ->
      return_if_nil(item.feed_url, :ok, fn ->
        encoded_feed = Base.url_encode64(item.feed_url, padding: false)
        encoded_item = encode_item(item.feed_url, item.guid)

        attrs = %{
          user_id: user_id,
          playlist_id: playlist_id,
          rss_source_feed: encoded_feed,
          rss_source_item: encoded_item,
          item_title: item.item_title,
          feed_title: item.feed_title,
          position: item.position || 0,
          inserted_at: now,
          updated_at: now
        }

        %PlaylistItem{}
        |> Ecto.Changeset.change(attrs)
        |> ProjectionsRepo.insert(
          on_conflict: {:replace, [:item_title, :feed_title, :position, :updated_at]},
          conflict_target: [:playlist_id, :rss_source_feed, :rss_source_item, :user_id]
        )
      end)
    end)
  end

  # ===== Collections Import =====

  defp import_collections(user_id, collections, now) do
    Enum.reduce(collections, %{imported: 0, skipped: 0, merged: 0}, fn collection, acc ->
      case import_collection(user_id, collection, now) do
        :imported -> %{acc | imported: acc.imported + 1}
        :skipped -> %{acc | skipped: acc.skipped + 1}
        :merged -> %{acc | merged: acc.merged + 1}
      end
    end)
  end

  defp import_collection(user_id, collection, now) do
    existing = get_existing_collection(user_id, collection)

    cond do
      is_nil(existing) ->
        create_collection(user_id, collection, now)
        :imported

      should_update_collection?(existing, collection) ->
        update_collection(existing, collection, now)
        :merged

      true ->
        :skipped
    end
  end

  defp get_existing_collection(user_id, collection) do
    query =
      if collection.id do
        from(c in Collection,
          where: c.user_id == ^user_id and c.id == ^collection.id and is_nil(c.deleted_at)
        )
      else
        from(c in Collection,
          where: c.user_id == ^user_id and c.title == ^collection.title and is_nil(c.deleted_at)
        )
      end

    ProjectionsRepo.one(query)
  end

  defp should_update_collection?(existing, incoming) do
    incoming_date = incoming.updated_at || DateTime.from_unix!(0)
    existing_date = existing.updated_at || DateTime.from_unix!(0)

    DateTime.compare(incoming_date, existing_date) == :gt
  end

  defp create_collection(user_id, collection, now) do
    collection_id = collection.id || Ecto.UUID.generate()

    attrs = %{
      id: collection_id,
      user_id: user_id,
      title: collection.title,
      description: collection.description,
      is_public: collection.is_public || false,
      color: collection.color,
      is_default: false,
      inserted_at: now,
      updated_at: now
    }

    case ProjectionsRepo.insert(%Collection{} |> Ecto.Changeset.change(attrs)) do
      {:ok, created} ->
        import_collection_feeds(created.id, collection.feeds, now)
      {:error, _} ->
        :error
    end
  end

  defp update_collection(existing, collection, now) do
    attrs = %{
      title: collection.title || existing.title,
      description: collection.description || existing.description,
      is_public: collection.is_public,
      color: collection.color || existing.color,
      updated_at: now
    }

    existing
    |> Ecto.Changeset.change(attrs)
    |> ProjectionsRepo.update()

    import_collection_feeds(existing.id, collection.feeds, now)
  end

  defp import_collection_feeds(_collection_id, [], _now), do: :ok
  defp import_collection_feeds(collection_id, feeds, now) do
    Enum.each(feeds, fn feed_url ->
      return_if_nil(feed_url, :ok, fn ->
        encoded_feed = Base.url_encode64(feed_url, padding: false)

        attrs = %{
          collection_id: collection_id,
          rss_source_feed: encoded_feed,
          inserted_at: now,
          updated_at: now
        }

        %CollectionSubscription{}
        |> Ecto.Changeset.change(attrs)
        |> ProjectionsRepo.insert(
          on_conflict: :nothing,
          conflict_target: [:collection_id, :rss_source_feed]
        )
      end)
    end)
  end

  # ===== Dry Run Stats =====

  defp calculate_dry_run_stats(_user_id, doc) do
    # This is a simplified version - just count items
    %{
      subscriptions: %{
        imported: length(doc.subscriptions),
        skipped: 0,
        merged: 0
      },
      play_statuses: %{
        imported: Enum.sum(Enum.map(doc.subscriptions, fn s -> length(s.play_statuses || []) end)),
        skipped: 0,
        merged: 0
      },
      playlists: %{
        imported: length(doc.playlists),
        skipped: 0,
        merged: 0
      },
      collections: %{
        imported: length(doc.collections),
        skipped: 0,
        merged: 0
      }
    }
  end

  # ===== Helpers =====

  defp return_if_nil(nil, default, _fun), do: default
  defp return_if_nil("", default, _fun), do: default
  defp return_if_nil(_value, _default, fun), do: fun.()

  defp generate_source_id(feed_url) do
    :crypto.hash(:sha256, feed_url)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp encode_item(feed_url, guid) do
    # Format: base64("feed_url,guid,")
    data = "#{feed_url},#{guid},"
    Base.url_encode64(data, padding: false)
  end
end
