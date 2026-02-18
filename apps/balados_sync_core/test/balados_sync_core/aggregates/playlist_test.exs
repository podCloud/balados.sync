defmodule BaladosSyncCore.Aggregates.PlaylistTest do
  @moduledoc """
  Tests for the Playlist aggregate.

  Tests the CQRS/ES implementation of playlists, including:
  - CreatePlaylist command
  - DeletePlaylist command
  - ChangePlaylistVisibility command
  - Event handling and aggregate state updates
  """

  use ExUnit.Case

  alias BaladosSyncCore.Aggregates.Playlist

  alias BaladosSyncCore.Commands.{
    CreatePlaylist,
    UpdatePlaylist,
    ReorderPlaylist,
    DeletePlaylist,
    ChangePlaylistVisibility,
    SnapshotPlaylist
  }

  alias BaladosSyncCore.Events.{
    PlaylistCreated,
    PlaylistUpdated,
    PlaylistReordered,
    PlaylistDeleted,
    PlaylistVisibilityChanged,
    PlaylistCheckpoint
  }

  describe "CreatePlaylist Command" do
    test "valid name creates playlist with generated UUID" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "My Favorites",
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.user_id == user_id
      assert event.name == "My Favorites"
      # UUID length
      assert byte_size(event.playlist_id) == 36
    end

    test "valid name with description creates playlist" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Tech Podcasts",
        description: "All my tech-related episodes",
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.name == "Tech Podcasts"
      assert event.description == "All my tech-related episodes"
    end

    test "provided playlist_id is used instead of generated UUID" do
      user_id = "user-123"
      playlist_id = "custom-playlist-id"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Custom ID Playlist",
        playlist_id: playlist_id,
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.playlist_id == playlist_id
    end

    test "empty name returns error" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "",
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :name_required}, result)
    end

    test "nil name returns error" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: nil,
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :name_required}, result)
    end

    test "duplicate playlist_id returns error" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      result = Playlist.execute(state, cmd)

      assert match?({:error, :playlist_already_exists}, result)
    end

    test "different playlist_ids don't conflict" do
      user_id = "user-123"
      existing_playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      result = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, result)
      assert result.name == "Second Playlist"
    end
  end

  describe "DeletePlaylist Command" do
    test "deletes existing playlist" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistDeleted{}, event)
      assert event.playlist_id == playlist_id
      assert event.user_id == user_id
    end

    test "returns error for non-existent playlist" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %DeletePlaylist{
        user_id: user_id,
        playlist_id: "nonexistent",
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :playlist_not_found}, result)
    end

    test "returns error for already deleted playlist" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
        user_id: user_id,
        playlists: %{}
      }

      cmd = %DeletePlaylist{
        user_id: user_id,
        playlist_id: playlist_id,
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :playlist_not_found}, result)
    end
  end

  describe "Event Application (apply/2)" do
    test "apply PlaylistCreated updates aggregate state" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "New Playlist",
        description: "Test description"
      }

      updated = Playlist.apply(state, event)

      assert playlist_id in Map.keys(updated.playlists)
      playlist = updated.playlists[playlist_id]
      assert playlist.name == "New Playlist"
      assert playlist.description == "Test description"
    end

    test "apply PlaylistCreated initializes empty items list" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "Empty Playlist"
      }

      updated = Playlist.apply(state, event)

      playlist = updated.playlists[playlist_id]
      assert playlist.items == []
    end

    test "apply PlaylistDeleted removes playlist from aggregate" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      updated = Playlist.apply(state, event)

      assert playlist_id not in Map.keys(updated.playlists)
      assert map_size(updated.playlists) == 0
    end

    test "apply PlaylistDeleted doesn't affect other playlists" do
      user_id = "user-123"
      playlist_to_delete = Ecto.UUID.generate()
      other_playlist = Ecto.UUID.generate()

      state = %Playlist{
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

      updated = Playlist.apply(state, event)

      assert playlist_to_delete not in Map.keys(updated.playlists)
      assert other_playlist in Map.keys(updated.playlists)
      assert updated.playlists[other_playlist].name == "Keep This"
    end
  end

  describe "ChangePlaylistVisibility Command" do
    test "makes playlist public" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistVisibilityChanged{}, event)
      assert event.user_id == user_id
      assert event.playlist_id == playlist_id
      assert event.is_public == true
    end

    test "makes playlist private" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistVisibilityChanged{}, event)
      assert event.is_public == false
    end

    test "returns error for non-existent playlist" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %ChangePlaylistVisibility{
        user_id: user_id,
        playlist_id: "nonexistent",
        is_public: true,
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :playlist_not_found}, result)
    end
  end

  describe "PlaylistVisibilityChanged Event Application" do
    test "apply PlaylistVisibilityChanged updates is_public to true" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      updated = Playlist.apply(state, event)

      assert updated.playlists[playlist_id].is_public == true
    end

    test "apply PlaylistVisibilityChanged updates is_public to false" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
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

      updated = Playlist.apply(state, event)

      assert updated.playlists[playlist_id].is_public == false
    end

    test "apply PlaylistVisibilityChanged doesn't affect other playlists" do
      user_id = "user-123"
      playlist_id = Ecto.UUID.generate()
      other_playlist = Ecto.UUID.generate()

      state = %Playlist{
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

      updated = Playlist.apply(state, event)

      assert updated.playlists[playlist_id].is_public == true
      assert updated.playlists[other_playlist].is_public == false
    end

    test "apply PlaylistVisibilityChanged handles missing playlist gracefully" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      event = %PlaylistVisibilityChanged{
        user_id: user_id,
        playlist_id: "nonexistent",
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      # Should not crash, just return state unchanged
      updated = Playlist.apply(state, event)

      assert updated == state
    end
  end

  describe "Device Queues (playlist_type)" do
    test "creates queue with playlist_type='queue'" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Device Queue",
        playlist_type: "queue",
        event_infos: %{device_id: "iphone-123"}
      }

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.playlist_type == "queue"
      assert event.name == "Device Queue"
    end

    test "creates playlist with explicit playlist_type='playlist'" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Explicit Playlist",
        playlist_type: "playlist",
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.playlist_type == "playlist"
    end

    test "defaults to playlist_type='playlist' when not specified" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Normal Playlist",
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert match?(%PlaylistCreated{}, event)
      assert event.playlist_type == "playlist"
    end

    test "rejects invalid playlist_type" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Invalid Type",
        playlist_type: "invalid_type",
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :invalid_playlist_type}, result)
    end

    test "rejects empty string playlist_type" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Empty Type",
        playlist_type: "",
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :invalid_playlist_type}, result)
    end

    test "rejects arbitrary string playlist_type" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}

      cmd = %CreatePlaylist{
        user_id: user_id,
        name: "Arbitrary Type",
        playlist_type: "smart_playlist",
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)

      assert match?({:error, :invalid_playlist_type}, result)
    end

    test "apply PlaylistCreated stores type in aggregate state" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "My Queue",
        description: nil,
        playlist_type: "queue",
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Playlist.apply(state, event)

      playlist = updated.playlists[playlist_id]
      assert playlist.type == "queue"
      assert playlist.name == "My Queue"
    end

    test "apply PlaylistCreated defaults type to 'playlist' when nil" do
      user_id = "user-123"
      state = %Playlist{user_id: user_id, playlists: %{}}
      playlist_id = Ecto.UUID.generate()

      event = %PlaylistCreated{
        user_id: user_id,
        playlist_id: playlist_id,
        name: "Legacy Playlist",
        description: nil,
        playlist_type: nil,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Playlist.apply(state, event)

      playlist = updated.playlists[playlist_id]
      assert playlist.type == "playlist"
    end
  end

  describe "UpdatePlaylist Command" do
    test "emits PlaylistUpdated for existing playlist" do
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
        user_id: "user-123",
        playlists: %{
          playlist_id => %{
            name: "Old Name",
            description: nil,
            type: "playlist",
            items: [],
            is_public: false
          }
        }
      }

      cmd = %UpdatePlaylist{
        user_id: "user-123",
        playlist: playlist_id,
        name: "New Name",
        description: "Updated description",
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert %PlaylistUpdated{} = event
      assert event.user_id == "user-123"
      assert event.playlist == playlist_id
      assert event.name == "New Name"
      assert event.description == "Updated description"
    end

    test "returns error for non-existent playlist" do
      state = %Playlist{user_id: "user-123", playlists: %{}}

      cmd = %UpdatePlaylist{
        user_id: "user-123",
        playlist: "nonexistent",
        name: "New Name",
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)
      assert match?({:error, :playlist_not_found}, result)
    end
  end

  describe "ReorderPlaylist Command" do
    test "emits PlaylistReordered for existing playlist" do
      playlist_id = Ecto.UUID.generate()
      new_items = [{"feed-2", "item-2"}, {"feed-1", "item-1"}]

      state = %Playlist{
        user_id: "user-123",
        playlists: %{
          playlist_id => %{
            name: "My Playlist",
            description: nil,
            type: "playlist",
            items: [{"feed-1", "item-1"}, {"feed-2", "item-2"}],
            is_public: false
          }
        }
      }

      cmd = %ReorderPlaylist{
        user_id: "user-123",
        playlist: playlist_id,
        items: new_items,
        event_infos: %{}
      }

      event = Playlist.execute(state, cmd)

      assert %PlaylistReordered{} = event
      assert event.user_id == "user-123"
      assert event.playlist == playlist_id
      assert event.items == new_items
    end

    test "returns error for non-existent playlist" do
      state = %Playlist{user_id: "user-123", playlists: %{}}

      cmd = %ReorderPlaylist{
        user_id: "user-123",
        playlist: "nonexistent",
        items: [],
        event_infos: %{}
      }

      result = Playlist.execute(state, cmd)
      assert match?({:error, :playlist_not_found}, result)
    end
  end

  describe "SnapshotPlaylist command" do
    test "emits PlaylistCheckpoint with current state" do
      playlist_id = Ecto.UUID.generate()

      state = %Playlist{
        user_id: "user-123",
        playlists: %{
          playlist_id => %{name: "Favorites", type: "playlist", items: [], is_public: false}
        }
      }

      event = Playlist.execute(state, %SnapshotPlaylist{user_id: "user-123"})

      assert %PlaylistCheckpoint{} = event
      assert event.user_id == "user-123"
      assert Map.has_key?(event.playlists, playlist_id)
    end

    test "emits checkpoint with empty playlists on nil state" do
      state = %Playlist{user_id: "user-123", playlists: nil}

      event = Playlist.execute(state, %SnapshotPlaylist{user_id: "user-123"})

      assert %PlaylistCheckpoint{} = event
      assert event.playlists == %{}
    end
  end

  describe "PlaylistCheckpoint apply" do
    test "restores full state including user_id" do
      state = %Playlist{user_id: nil, playlists: nil}

      playlists = %{
        "pl-1" => %{name: "Test", type: "playlist", items: [], is_public: false}
      }

      event = %PlaylistCheckpoint{
        user_id: "user-123",
        playlists: playlists,
        timestamp: DateTime.utc_now()
      }

      updated = Playlist.apply(state, event)

      assert updated.user_id == "user-123"
      assert updated.playlists == playlists
    end
  end
end
