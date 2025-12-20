defmodule BaladosSyncProjections.Projectors.PlaylistsProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "PlaylistsProjector"

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Events.{
    EpisodeSaved,
    EpisodeUnsaved,
    PlaylistCreated,
    PlaylistUpdated,
    PlaylistReordered,
    PlaylistDeleted,
    PlaylistVisibilityChanged,
    UserCheckpoint
  }

  alias BaladosSyncProjections.Schemas.{Playlist, PlaylistItem}

  project(%PlaylistCreated{} = event, _metadata, fn multi ->
    Logger.info("Playlist created",
      action: :playlist_created,
      user_id: event.user_id,
      playlist_id: event.playlist_id,
      playlist_name: event.name
    )

    playlist_attrs = %{
      id: event.playlist_id,
      user_id: event.user_id,
      name: event.name,
      description: event.description
    }

    Ecto.Multi.insert(
      multi,
      :playlist,
      %Playlist{} |> Ecto.Changeset.change(playlist_attrs),
      on_conflict: {:replace, [:name, :description, :updated_at]},
      conflict_target: [:id, :user_id]
    )
  end)

  project(%PlaylistDeleted{} = event, _metadata, fn multi ->
    Logger.info("Playlist deleted",
      action: :playlist_deleted,
      user_id: event.user_id,
      playlist_id: event.playlist_id
    )

    # Soft delete playlist and all its items
    multi =
      Ecto.Multi.update_all(
        multi,
        :playlist,
        from(p in Playlist,
          where: p.id == ^event.playlist_id and p.user_id == ^event.user_id
        ),
        set: [deleted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()]
      )

    # Also soft delete all items in the playlist
    Ecto.Multi.update_all(
      multi,
      :playlist_items,
      from(pi in PlaylistItem,
        where: pi.playlist_id == ^event.playlist_id and pi.user_id == ^event.user_id
      ),
      set: [deleted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()]
    )
  end)

  project(%EpisodeSaved{} = event, _metadata, fn multi ->
    # Create or get playlist
    playlist_attrs = %{
      id: event.playlist,
      user_id: event.user_id,
      name: event.playlist
    }

    # Upsert playlist
    multi =
      Ecto.Multi.insert(
        multi,
        :playlist,
        %Playlist{} |> Ecto.Changeset.change(playlist_attrs),
        on_conflict: {:replace, [:name, :updated_at]},
        conflict_target: [:id, :user_id]
      )

    # Add item to playlist (create new item entry)
    item_attrs = %{
      user_id: event.user_id,
      playlist_id: event.playlist,
      rss_source_feed: event.rss_source_feed,
      rss_source_item: event.rss_source_item,
      item_title: event.item_title,
      feed_title: event.feed_title
    }

    Ecto.Multi.insert(
      multi,
      :playlist_item,
      %PlaylistItem{} |> Ecto.Changeset.change(item_attrs),
      on_conflict: {:replace, [:item_title, :feed_title, :updated_at]},
      conflict_target: [:playlist_id, :rss_source_feed, :rss_source_item, :user_id]
    )
  end)

  project(%EpisodeUnsaved{} = event, _metadata, fn multi ->
    # Mark item as deleted instead of hard delete (soft delete)
    Ecto.Multi.update_all(
      multi,
      :playlist_item,
      from(pi in PlaylistItem,
        where:
          pi.user_id == ^event.user_id and
            pi.playlist_id == ^event.playlist and
            pi.rss_source_feed == ^event.rss_source_feed and
            pi.rss_source_item == ^event.rss_source_item
      ),
      set: [deleted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()]
    )
  end)

  project(%PlaylistUpdated{} = event, _metadata, fn multi ->
    Logger.info("Playlist updated",
      action: :playlist_updated,
      user_id: event.user_id,
      playlist_id: event.playlist,
      updated_fields: Enum.filter([
        if(event.name, do: :name),
        if(event.description, do: :description)
      ], & &1)
    )

    updates = []
    updates = if event.name, do: updates ++ [name: event.name], else: updates
    updates = if event.description, do: updates ++ [description: event.description], else: updates
    updates = updates ++ [updated_at: DateTime.utc_now()]

    Ecto.Multi.update_all(
      multi,
      :playlist,
      from(p in Playlist,
        where: p.id == ^event.playlist and p.user_id == ^event.user_id
      ),
      set: updates
    )
  end)

  project(%PlaylistReordered{} = event, _metadata, fn multi ->
    # Reorder items by updating positions
    Enum.reduce(event.items, multi, fn {feed, item, position}, acc ->
      Ecto.Multi.update_all(
        acc,
        {:playlist_item, {feed, item}},
        from(pi in PlaylistItem,
          where:
            pi.user_id == ^event.user_id and
              pi.playlist_id == ^event.playlist and
              pi.rss_source_feed == ^feed and
              pi.rss_source_item == ^item
        ),
        set: [position: position, updated_at: DateTime.utc_now()]
      )
    end)
  end)

  project(%PlaylistVisibilityChanged{} = event, _metadata, fn multi ->
    Logger.info("Playlist visibility changed",
      action: :playlist_visibility_changed,
      user_id: event.user_id,
      playlist_id: event.playlist_id,
      is_public: event.is_public
    )

    Ecto.Multi.update_all(
      multi,
      :playlist,
      from(p in Playlist,
        where: p.id == ^event.playlist_id and p.user_id == ^event.user_id
      ),
      set: [is_public: event.is_public, updated_at: DateTime.utc_now()]
    )
  end)

  project(%UserCheckpoint{} = event, _metadata, fn multi ->
    # Upsert all playlists and items from checkpoint
    multi =
      Enum.reduce(event.playlists || %{}, multi, fn {playlist_id, playlist}, acc ->
        playlist_changes = %{
          id: playlist_id,
          user_id: event.user_id,
          name: playlist.name,
          description: playlist.description
        }

        acc =
          Ecto.Multi.insert(
            acc,
            {:playlist, playlist_id},
            %Playlist{} |> Ecto.Changeset.change(playlist_changes),
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: [:id, :user_id]
          )

        # Upsert all items in the playlist
        Enum.reduce(playlist.items || [], acc, fn {feed, item}, item_acc ->
          item_attrs = %{
            user_id: event.user_id,
            playlist_id: playlist_id,
            rss_source_feed: feed,
            rss_source_item: item
          }

          Ecto.Multi.insert(
            item_acc,
            {:playlist_item, {playlist_id, feed, item}},
            %PlaylistItem{} |> Ecto.Changeset.change(item_attrs),
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: [:playlist_id, :rss_source_feed, :rss_source_item, :user_id]
          )
        end)
      end)

    multi
  end)
end
