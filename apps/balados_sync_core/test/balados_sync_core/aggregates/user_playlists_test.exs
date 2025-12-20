defmodule BaladosSyncCore.Aggregates.UserPlaylistsTest do
  @moduledoc """
  Tests for Playlists functionality in the User aggregate.

  Tests the CQRS/ES implementation of playlists, including:
  - CreatePlaylist command
  - DeletePlaylist command
  - Event handling and aggregate state updates
  """

  use ExUnit.Case

  alias BaladosSyncCore.Aggregates.User

  alias BaladosSyncCore.Commands.{
    CreatePlaylist,
    DeletePlaylist,
    ChangePlaylistVisibility
  }

  alias BaladosSyncCore.Events.{
    PlaylistCreated,
    PlaylistDeleted,
    PlaylistVisibilityChanged
  }

  describe "CreatePlaylist Command" do
    test "valid name creates playlist with generated UUID" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "My Favorites",
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.user_id == user_id
      assert event.name == "My Favorites"
      # UUID length
      assert byte_size(event.playlist_id) == 36
    end

    test "valid name with description creates playlist" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Tech Podcasts",
        description: "All my tech-related episodes",
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.name == "Tech Podcasts"
      assert event.description == "All my tech-related episodes"
    end

    test "provided playlist_id is used instead of generated UUID" do
      user_id = "user-123"
      playlist_id = "custom-playlist-id"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Custom ID Playlist",
        playlist_id: playlist_id,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.playlist_id == playlist_id
    end

    test "empty name returns error" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :name_required}, result)
    end

    test "nil name returns error" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: nil,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :name_required}, result)
    end

    test "duplicate playlist_id returns error" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "Existing Playlist", items: []}
        }
      }

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Another Playlist",
        playlist_id: playlist_id,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :playlist_already_exists}, result)
    end

    test "different playlist_ids don't conflict" do
      user_id = "user-123"
      existing_playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          existing_playlist_id => %{name: "First Playlist", items: []}
        }
      }

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Second Playlist",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?(%PlaylistCreated{}, result)
      assert result.name == "Second Playlist"
    end
  end

  describe "DeletePlaylist Command" do
    test "deletes existing playlist" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "To Delete", items: []}
        }
      }

      cmd = %DeletePlaylist{
        user_id: user_id,
        playlist_id: playlist_id,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%PlaylistDeleted{}, event)
      assert event.playlist_id == playlist_id
      assert event.user_id == user_id
    end

    test "returns error for non-existent playlist" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %DeletePlaylist{
        user_id: user_id,
        playlist_id: "nonexistent",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :playlist_not_found}, result)
    end

    test "returns error for already deleted playlist" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      # Playlist doesn't exist in aggregate state (already deleted or never existed)
      user = %User{
        user_id: user_id,
        playlists: %{}
      }

      cmd = %DeletePlaylist{
        user_id: user_id,
        playlist_id: playlist_id,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :playlist_not_found}, result)
    end
  end

  describe "Event Application (apply/2)" do
    test "apply PlaylistCreated updates aggregate state" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "New Playlist",
        description: "Test description"
      }

      updated_user = User.apply(user, event)

      assert playlist_id in Map.keys(updated_user.playlists)
      playlist = updated_user.playlists[playlist_id]
      assert playlist.name == "New Playlist"
      assert playlist.description == "Test description"
    end

    test "apply PlaylistCreated initializes empty items list" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "Empty Playlist"
      }

      updated_user = User.apply(user, event)

      playlist = updated_user.playlists[playlist_id]
      assert playlist.items == []
    end

    test "apply PlaylistDeleted removes playlist from aggregate" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "To Remove", items: []}
        }
      }

      event = %PlaylistDeleted{
        user_id: user_id,
        playlist_id: playlist_id,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert playlist_id not in Map.keys(updated_user.playlists)
      assert map_size(updated_user.playlists) == 0
    end

    test "apply PlaylistDeleted doesn't affect other playlists" do
      user_id = "user-123"
      playlist_to_delete = Ecto.UUID.generate()
      other_playlist = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_to_delete => %{name: "To Delete", items: []},
          other_playlist => %{name: "Keep This", items: []}
        }
      }

      event = %PlaylistDeleted{
        user_id: user_id,
        playlist_id: playlist_to_delete,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert playlist_to_delete not in Map.keys(updated_user.playlists)
      assert other_playlist in Map.keys(updated_user.playlists)
      assert updated_user.playlists[other_playlist].name == "Keep This"
    end
  end

  describe "ChangePlaylistVisibility Command" do
    test "makes playlist public" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "My Playlist", items: [], is_public: false}
        }
      }

      cmd = %ChangePlaylistVisibility{
        user_id: user_id,
        playlist_id: playlist_id,
        is_public: true,
        event_infos: %{device_id: "web", device_name: "Web Browser"}
      }

      event = User.execute(user, cmd)

      assert match?(%PlaylistVisibilityChanged{}, event)
      assert event.user_id == user_id
      assert event.playlist_id == playlist_id
      assert event.is_public == true
    end

    test "makes playlist private" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "My Playlist", items: [], is_public: true}
        }
      }

      cmd = %ChangePlaylistVisibility{
        user_id: user_id,
        playlist_id: playlist_id,
        is_public: false,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%PlaylistVisibilityChanged{}, event)
      assert event.is_public == false
    end

    test "returns error for non-existent playlist" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      cmd = %ChangePlaylistVisibility{
        user_id: user_id,
        playlist_id: "nonexistent",
        is_public: true,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :playlist_not_found}, result)
    end
  end

  describe "PlaylistVisibilityChanged Event Application" do
    test "apply PlaylistVisibilityChanged updates is_public to true" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "My Playlist", items: [], is_public: false}
        }
      }

      event = %PlaylistVisibilityChanged{
        user_id: user_id,
        playlist_id: playlist_id,
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.playlists[playlist_id].is_public == true
    end

    test "apply PlaylistVisibilityChanged updates is_public to false" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "My Playlist", items: [], is_public: true}
        }
      }

      event = %PlaylistVisibilityChanged{
        user_id: user_id,
        playlist_id: playlist_id,
        is_public: false,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.playlists[playlist_id].is_public == false
    end

    test "apply PlaylistVisibilityChanged doesn't affect other playlists" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()
      other_playlist = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        playlists: %{
          playlist_id => %{name: "Target", items: [], is_public: false},
          other_playlist => %{name: "Other", items: [], is_public: false}
        }
      }

      event = %PlaylistVisibilityChanged{
        user_id: user_id,
        playlist_id: playlist_id,
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.playlists[playlist_id].is_public == true
      assert updated_user.playlists[other_playlist].is_public == false
    end

    test "apply PlaylistVisibilityChanged handles missing playlist gracefully" do
      user_id = "user-123"
      user = %User{user_id: user_id, playlists: %{}}

      event = %PlaylistVisibilityChanged{
        user_id: user_id,
        playlist_id: "nonexistent",
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      # Should not crash, just return user unchanged
      updated_user = User.apply(user, event)

      assert updated_user == user
    end
  end
end
