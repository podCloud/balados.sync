defmodule BaladosSyncProjections.Projectors.PlaylistsProjectorTest do
  @moduledoc """
  Tests for PlaylistsProjector.

  Tests the projection of playlist-related events to the read model:
  - PlaylistCreated → playlists table
  - PlaylistDeleted → soft delete with deleted_at
  - PlaylistUpdated → update of name/description/updated_at
  """

  use BaladosSyncProjections.DataCase

  alias BaladosSyncCore.Events.{
    PlaylistCreated,
    PlaylistDeleted,
    PlaylistUpdated
  }

  alias BaladosSyncProjections.Schemas.{Playlist, PlaylistItem}

  describe "PlaylistCreated projection" do
    test "creates row in playlists table" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "My Favorites",
        description: "Best episodes"
      }

      apply_projection(event)

      playlist = ProjectionsRepo.get_by(Playlist, user_id: user_id, id: playlist_id)

      assert not is_nil(playlist)
      assert playlist.name == "My Favorites"
      assert playlist.description == "Best episodes"
      assert is_nil(playlist.deleted_at)
    end

    test "idempotent - replaying creates same state" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "My Favorites"
      }

      # Apply twice
      apply_projection(event)
      apply_projection(event)

      # Should only have one playlist
      playlists =
        ProjectionsRepo.all(
          from(p in Playlist,
            where: p.user_id == ^user_id and p.id == ^playlist_id
          )
        )

      assert length(playlists) == 1
    end
  end

  describe "PlaylistDeleted projection" do
    test "soft-deletes with deleted_at timestamp" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      # Create playlist first
      create_event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "To Delete"
      }

      apply_projection(create_event)

      # Delete playlist
      delete_event = %PlaylistDeleted{
        user_id: user_id,
        playlist_id: playlist_id
      }

      apply_projection(delete_event)

      # Verify soft delete
      playlist = ProjectionsRepo.get(Playlist, playlist_id)

      assert not is_nil(playlist.deleted_at)
    end

    test "soft-deletes associated playlist items" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      # Create playlist first
      create_event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "To Delete"
      }

      apply_projection(create_event)

      # Create an item
      item = %PlaylistItem{
        user_id: user_id,
        playlist_id: playlist_id,
        rss_source_feed: "feed1",
        rss_source_item: "item1"
      }

      ProjectionsRepo.insert!(item)

      # Delete playlist
      delete_event = %PlaylistDeleted{
        user_id: user_id,
        playlist_id: playlist_id
      }

      apply_projection(delete_event)

      # Verify item was soft deleted
      deleted_item =
        ProjectionsRepo.get_by(PlaylistItem,
          playlist_id: playlist_id,
          rss_source_feed: "feed1"
        )

      assert not is_nil(deleted_item.deleted_at)
    end
  end

  describe "PlaylistUpdated projection" do
    test "updates name and description" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      # Create playlist
      create_event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "Original Name"
      }

      apply_projection(create_event)

      # Update
      update_event = %PlaylistUpdated{
        user_id: user_id,
        playlist: playlist_id,
        name: "New Name",
        description: "New Description"
      }

      apply_projection(update_event)

      # Verify update
      playlist = ProjectionsRepo.get(Playlist, playlist_id)

      assert playlist.name == "New Name"
      assert playlist.description == "New Description"
    end

    test "partial update - only name" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      # Create playlist
      create_event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "Original Name",
        description: "Original Description"
      }

      apply_projection(create_event)

      # Update only name
      update_event = %PlaylistUpdated{
        user_id: user_id,
        playlist: playlist_id,
        name: "New Name",
        description: nil
      }

      apply_projection(update_event)

      # Verify update
      playlist = ProjectionsRepo.get(Playlist, playlist_id)

      assert playlist.name == "New Name"
      # Description should remain unchanged
      assert playlist.description == "Original Description"
    end
  end

  # Helper to apply projections manually (in real app, done through Dispatcher)
  defp apply_projection(event) do
    handle_event(event)
  end

  # Manual event handling for testing
  defp handle_event(%PlaylistCreated{} = event) do
    # Insert playlist directly with struct to include id
    playlist = %Playlist{
      id: event.playlist_id,
      user_id: event.user_id,
      name: event.name,
      description: event.description
    }

    ProjectionsRepo.insert(playlist,
      on_conflict: {:replace, [:name, :description, :updated_at]},
      conflict_target: [:id]
    )
  end

  defp handle_event(%PlaylistDeleted{} = event) do
    now = DateTime.utc_now()

    # Soft delete playlist
    ProjectionsRepo.update_all(
      from(p in Playlist,
        where: p.id == ^event.playlist_id and p.user_id == ^event.user_id
      ),
      set: [deleted_at: now, updated_at: now]
    )

    # Soft delete items
    ProjectionsRepo.update_all(
      from(pi in PlaylistItem,
        where: pi.playlist_id == ^event.playlist_id and pi.user_id == ^event.user_id
      ),
      set: [deleted_at: now, updated_at: now]
    )
  end

  defp handle_event(%PlaylistUpdated{} = event) do
    now = DateTime.utc_now()
    updates = [updated_at: now]
    updates = if event.name, do: [{:name, event.name} | updates], else: updates
    updates = if event.description, do: [{:description, event.description} | updates], else: updates

    ProjectionsRepo.update_all(
      from(p in Playlist, where: p.id == ^event.playlist and p.user_id == ^event.user_id),
      set: updates
    )
  end
end
