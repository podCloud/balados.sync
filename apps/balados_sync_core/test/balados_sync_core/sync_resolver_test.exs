defmodule BaladosSyncCore.SyncResolverTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.SyncResolver

  describe "resolve_subscription/2" do
    test "local wins when more recent" do
      local = %{
        subscribed_at: ~U[2024-01-20 10:00:00Z],
        unsubscribed_at: nil
      }
      remote = %{
        subscribed_at: ~U[2024-01-19 10:00:00Z],
        unsubscribed_at: nil
      }

      {:ok, winner, resolution, conflict} = SyncResolver.resolve_subscription(local, remote)

      assert resolution == :local_wins
      assert winner.subscribed_at == ~U[2024-01-20 10:00:00Z]
      assert conflict == nil
    end

    test "remote wins when more recent" do
      local = %{
        subscribed_at: ~U[2024-01-19 10:00:00Z],
        unsubscribed_at: nil
      }
      remote = %{
        subscribed_at: ~U[2024-01-20 10:00:00Z],
        unsubscribed_at: nil
      }

      {:ok, winner, resolution, _conflict} = SyncResolver.resolve_subscription(local, remote)

      assert resolution == :remote_wins
      assert winner.subscribed_at == ~U[2024-01-20 10:00:00Z]
    end

    test "unsubscribed_at takes precedence when more recent" do
      local = %{
        subscribed_at: ~U[2024-01-18 10:00:00Z],
        unsubscribed_at: ~U[2024-01-20 10:00:00Z]
      }
      remote = %{
        subscribed_at: ~U[2024-01-19 10:00:00Z],
        unsubscribed_at: nil
      }

      {:ok, _winner, resolution, _conflict} = SyncResolver.resolve_subscription(local, remote)

      assert resolution == :local_wins
    end

    test "prefers subscribed when timestamps equal" do
      local = %{
        subscribed_at: ~U[2024-01-20 10:00:00Z],
        unsubscribed_at: nil
      }
      remote = %{
        subscribed_at: nil,
        unsubscribed_at: ~U[2024-01-20 10:00:00Z]
      }

      {:ok, winner, resolution, _conflict} = SyncResolver.resolve_subscription(local, remote)

      assert resolution == :merged
      assert winner.subscribed_at == ~U[2024-01-20 10:00:00Z]
      assert winner.unsubscribed_at == nil
    end
  end

  describe "resolve_play_position/2" do
    test "higher position wins" do
      local = %{position: 1500, played: false, updated_at: ~U[2024-01-20 10:30:00Z]}
      remote = %{position: 2000, played: false, updated_at: ~U[2024-01-20 10:25:00Z]}

      {:ok, winner, resolution, conflict} = SyncResolver.resolve_play_position(local, remote)

      assert resolution == :remote_wins
      assert winner.position == 2000
      assert conflict != nil
      assert conflict.type == :play_position
      assert conflict.reason =~ "Higher remote position"
    end

    test "local reset flag overrides position" do
      local = %{position: 0, played: false, updated_at: ~U[2024-01-20 10:30:00Z], reset: true}
      remote = %{position: 2000, played: false, updated_at: ~U[2024-01-20 10:25:00Z]}

      {:ok, winner, resolution, conflict} = SyncResolver.resolve_play_position(local, remote)

      assert resolution == :local_wins
      assert winner.position == 0
      assert conflict.reason =~ "Local reset flag"
    end

    test "played status wins over position" do
      local = %{position: 1500, played: true, updated_at: ~U[2024-01-20 10:30:00Z]}
      remote = %{position: 2000, played: false, updated_at: ~U[2024-01-20 10:25:00Z]}

      {:ok, winner, resolution, conflict} = SyncResolver.resolve_play_position(local, remote)

      assert resolution == :local_wins
      assert winner.played == true
      assert conflict.reason =~ "Local marked as played"
    end

    test "remote played status wins" do
      local = %{position: 1500, played: false, updated_at: ~U[2024-01-20 10:30:00Z]}
      remote = %{position: 1000, played: true, updated_at: ~U[2024-01-20 10:25:00Z]}

      {:ok, winner, resolution, conflict} = SyncResolver.resolve_play_position(local, remote)

      assert resolution == :remote_wins
      assert winner.played == true
      assert conflict.reason =~ "Remote marked as played"
    end

    test "same position uses timestamp" do
      local = %{position: 1500, played: false, updated_at: ~U[2024-01-20 10:30:00Z]}
      remote = %{position: 1500, played: false, updated_at: ~U[2024-01-20 10:25:00Z]}

      {:ok, _winner, resolution, conflict} = SyncResolver.resolve_play_position(local, remote)

      assert resolution == :local_wins
      assert conflict == nil
    end
  end

  describe "resolve_playlist/3" do
    test "merges items from both sources" do
      local = %{
        name: "My Playlist",
        description: "Local desc",
        is_public: false,
        items: [
          %{rss_source_feed: "feed1", rss_source_item: "item1", position: 0},
          %{rss_source_feed: "feed1", rss_source_item: "item2", position: 1}
        ],
        updated_at: ~U[2024-01-20 10:00:00Z]
      }

      remote = %{
        name: "Updated Playlist",
        description: "Remote desc",
        is_public: true,
        items: [
          %{rss_source_feed: "feed1", rss_source_item: "item1", position: 0},
          %{rss_source_feed: "feed1", rss_source_item: "item3", position: 1}
        ],
        updated_at: ~U[2024-01-20 11:00:00Z]
      }

      base = %{
        items: [
          %{rss_source_feed: "feed1", rss_source_item: "item1", position: 0}
        ]
      }

      {:ok, winner, resolution, _conflict} = SyncResolver.resolve_playlist(local, remote, base)

      assert resolution == :merged
      # Metadata from remote (more recent)
      assert winner.name == "Updated Playlist"
      assert winner.is_public == true

      # Items merged: item1 (base), item2 (local), item3 (remote)
      item_keys = Enum.map(winner.items, fn item ->
        {item[:rss_source_feed] || item["rss_source_feed"],
         item[:rss_source_item] || item["rss_source_item"]}
      end)

      assert {"feed1", "item1"} in item_keys
      assert {"feed1", "item2"} in item_keys
      assert {"feed1", "item3"} in item_keys
    end

    test "LWW for metadata when same items" do
      local = %{
        name: "Old Name",
        items: [%{rss_source_feed: "feed1", rss_source_item: "item1", position: 0}],
        updated_at: ~U[2024-01-20 10:00:00Z]
      }

      remote = %{
        name: "New Name",
        items: [%{rss_source_feed: "feed1", rss_source_item: "item1", position: 0}],
        updated_at: ~U[2024-01-20 11:00:00Z]
      }

      {:ok, winner, resolution, _conflict} = SyncResolver.resolve_playlist(local, remote, nil)

      assert resolution == :remote_wins
      assert winner.name == "New Name"
    end
  end

  describe "resolve_privacy/2" do
    test "local wins when more recent" do
      local = %{privacy: "public", updated_at: ~U[2024-01-20 10:00:00Z]}
      remote = %{privacy: "private", updated_at: ~U[2024-01-19 10:00:00Z]}

      {:ok, winner, resolution, _conflict} = SyncResolver.resolve_privacy(local, remote)

      assert resolution == :local_wins
      assert winner.privacy == "public"
    end

    test "remote wins when more recent" do
      local = %{privacy: "public", updated_at: ~U[2024-01-19 10:00:00Z]}
      remote = %{privacy: "private", updated_at: ~U[2024-01-20 10:00:00Z]}

      {:ok, winner, resolution, _conflict} = SyncResolver.resolve_privacy(local, remote)

      assert resolution == :remote_wins
      assert winner.privacy == "private"
    end
  end

  describe "resolve_sync/2" do
    test "handles empty data" do
      {:ok, resolved, conflicts} = SyncResolver.resolve_sync(%{}, %{})

      assert resolved.subscriptions == %{}
      assert resolved.play_statuses == %{}
      assert resolved.playlists == %{}
      assert conflicts == []
    end

    test "merges non-overlapping data" do
      local = %{
        subscriptions: %{
          "feed1" => %{subscribed_at: ~U[2024-01-20 10:00:00Z], unsubscribed_at: nil}
        }
      }

      remote = %{
        subscriptions: %{
          "feed2" => %{subscribed_at: ~U[2024-01-19 10:00:00Z], unsubscribed_at: nil}
        }
      }

      {:ok, resolved, conflicts} = SyncResolver.resolve_sync(local, remote)

      assert Map.has_key?(resolved.subscriptions, "feed1")
      assert Map.has_key?(resolved.subscriptions, "feed2")
      assert conflicts == []
    end

    test "records conflicts for overlapping play positions" do
      local = %{
        play_statuses: %{
          "item1" => %{position: 1500, played: false, updated_at: ~U[2024-01-20 10:30:00Z]}
        }
      }

      remote = %{
        play_statuses: %{
          "item1" => %{position: 2000, played: false, updated_at: ~U[2024-01-20 10:25:00Z]}
        }
      }

      {:ok, resolved, conflicts} = SyncResolver.resolve_sync(local, remote)

      # Remote wins (higher position)
      assert resolved.play_statuses["item1"].position == 2000
      # Conflict recorded
      assert length(conflicts) == 1
      assert hd(conflicts).type == :play_position
    end
  end
end
