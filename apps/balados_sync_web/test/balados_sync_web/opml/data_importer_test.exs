defmodule BaladosSyncWeb.Opml.DataImporterTest do
  @moduledoc """
  Tests for OPML DataImporter conflict resolution strategies.

  These tests verify that the DataImporter correctly handles:
  - Subscription import with Last-Write-Wins (LWW) conflict resolution
  - Play status import with highest-progress-wins conflict resolution
  - Playlist and collection import/merge behavior
  """
  use BaladosSyncWeb.DataCase

  alias BaladosSyncWeb.Opml.DataImporter
  alias BaladosSyncProjections.ProjectionsRepo

  @moduletag :data_importer

  setup do
    user_id = Ecto.UUID.generate()
    {:ok, user_id: user_id}
  end

  describe "subscription conflict resolution (Last-Write-Wins)" do
    test "imports new subscription when none exists", %{user_id: user_id} do
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: "https://example.com/feed1.xml",
            title: "Test Podcast",
            subscribed_at: ~U[2026-01-10 10:00:00Z],
            privacy: "public"
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      # Note: The actual subscription creation goes through CQRS (async),
      # so we only verify the stats here. The subscription will be created
      # via the Subscribe command which is tested elsewhere.
      assert stats.subscriptions.imported == 1
      assert stats.subscriptions.skipped == 0
      assert stats.subscriptions.merged == 0
    end

    test "merges subscription when incoming is newer", %{user_id: user_id} do
      # Create existing subscription directly in projection (bypassing CQRS for test setup)
      feed_url = "https://example.com/existing.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      old_date = ~U[2026-01-01 10:00:00Z]

      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.Subscription{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_id: "existing-feed",
        subscribed_at: old_date
      })

      # Import newer subscription
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Updated Podcast",
            subscribed_at: ~U[2026-01-10 10:00:00Z],
            privacy: "private"
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.subscriptions.merged == 1
      assert stats.subscriptions.imported == 0
    end

    test "skips subscription when incoming is older", %{user_id: user_id} do
      # Create existing subscription directly in projection with recent date
      feed_url = "https://example.com/existing.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      recent_date = ~U[2026-01-10 10:00:00Z]

      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.Subscription{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_id: "existing-feed",
        subscribed_at: recent_date
      })

      # Import older subscription
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Old Podcast",
            subscribed_at: ~U[2026-01-01 10:00:00Z],
            privacy: "public"
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.subscriptions.skipped == 1
      assert stats.subscriptions.imported == 0
      assert stats.subscriptions.merged == 0
    end

    test "skips subscription with nil feed_url", %{user_id: user_id} do
      doc = build_document(
        subscriptions: [
          build_subscription(feed_url: nil, title: "No URL Podcast")
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.subscriptions.skipped == 1
    end
  end

  describe "play status conflict resolution (highest progress wins)" do
    test "imports new play status when none exists", %{user_id: user_id} do
      feed_url = "https://example.com/feed.xml"

      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Test Podcast",
            play_statuses: [
              build_play_status(
                guid: "episode-1",
                position: 300,
                played: false,
                updated_at: ~U[2026-01-10 10:00:00Z]
              )
            ]
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.play_statuses.imported == 1

      # Verify play status was created
      encoded_item = encode_item(feed_url, "episode-1")
      ps = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.PlayStatus, user_id: user_id, rss_source_item: encoded_item)
      assert ps != nil
      assert ps.position == 300
      assert ps.played == false
    end

    test "merges when incoming has higher position", %{user_id: user_id} do
      feed_url = "https://example.com/feed.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      encoded_item = encode_item(feed_url, "episode-1")

      # Create existing play status with lower position
      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.PlayStatus{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_item: encoded_item,
        position: 100,
        played: false,
        updated_at: ~U[2026-01-01 10:00:00Z]
      })

      # Import with higher position
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Test Podcast",
            play_statuses: [
              build_play_status(
                guid: "episode-1",
                position: 500,
                played: false,
                updated_at: ~U[2026-01-05 10:00:00Z]
              )
            ]
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.play_statuses.merged == 1

      # Verify position was updated to max
      ps = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.PlayStatus, user_id: user_id, rss_source_item: encoded_item)
      assert ps.position == 500
    end

    test "merges when incoming is newer even with same position", %{user_id: user_id} do
      feed_url = "https://example.com/feed.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      encoded_item = encode_item(feed_url, "episode-1")

      # Create existing play status
      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.PlayStatus{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_item: encoded_item,
        position: 300,
        played: false,
        updated_at: ~U[2026-01-01 10:00:00Z]
      })

      # Import with same position but newer date
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Test Podcast",
            play_statuses: [
              build_play_status(
                guid: "episode-1",
                position: 300,
                played: true,
                updated_at: ~U[2026-01-10 10:00:00Z]
              )
            ]
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.play_statuses.merged == 1

      # Verify played was updated (played is OR'd)
      ps = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.PlayStatus, user_id: user_id, rss_source_item: encoded_item)
      assert ps.played == true
    end

    test "takes max position when merging", %{user_id: user_id} do
      feed_url = "https://example.com/feed.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      encoded_item = encode_item(feed_url, "episode-1")

      # Create existing play status with higher position
      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.PlayStatus{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_item: encoded_item,
        position: 800,
        played: false,
        updated_at: ~U[2026-01-01 10:00:00Z]
      })

      # Import with lower position but newer date (should take max position)
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Test Podcast",
            play_statuses: [
              build_play_status(
                guid: "episode-1",
                position: 300,
                played: false,
                updated_at: ~U[2026-01-10 10:00:00Z]
              )
            ]
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.play_statuses.merged == 1

      # Verify position kept max value (800)
      ps = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.PlayStatus, user_id: user_id, rss_source_item: encoded_item)
      assert ps.position == 800
    end

    test "ORs played flag when merging", %{user_id: user_id} do
      feed_url = "https://example.com/feed.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      encoded_item = encode_item(feed_url, "episode-1")

      # Create existing play status with played=true
      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.PlayStatus{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_item: encoded_item,
        position: 100,
        played: true,
        updated_at: ~U[2026-01-01 10:00:00Z]
      })

      # Import with played=false but higher position (should keep played=true)
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Test Podcast",
            play_statuses: [
              build_play_status(
                guid: "episode-1",
                position: 500,
                played: false,
                updated_at: ~U[2026-01-10 10:00:00Z]
              )
            ]
          )
        ]
      )

      {:ok, _stats} = DataImporter.import(user_id, doc)

      ps = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.PlayStatus, user_id: user_id, rss_source_item: encoded_item)
      assert ps.played == true
    end

    test "skips when incoming is older and has lower position", %{user_id: user_id} do
      feed_url = "https://example.com/feed.xml"
      encoded_feed = Base.url_encode64(feed_url, padding: false)
      encoded_item = encode_item(feed_url, "episode-1")

      # Create existing play status with higher position and newer date
      {:ok, _} = ProjectionsRepo.insert(%BaladosSyncProjections.Schemas.PlayStatus{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_item: encoded_item,
        position: 800,
        played: true,
        updated_at: ~U[2026-01-10 10:00:00Z]
      })

      # Import with lower position and older date
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: feed_url,
            title: "Test Podcast",
            play_statuses: [
              build_play_status(
                guid: "episode-1",
                position: 100,
                played: false,
                updated_at: ~U[2026-01-01 10:00:00Z]
              )
            ]
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.play_statuses.skipped == 1

      # Verify nothing changed
      ps = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.PlayStatus, user_id: user_id, rss_source_item: encoded_item)
      assert ps.position == 800
      assert ps.played == true
    end
  end

  describe "dry run mode" do
    test "counts items without importing", %{user_id: user_id} do
      doc = build_document(
        subscriptions: [
          build_subscription(
            feed_url: "https://example.com/feed1.xml",
            play_statuses: [
              build_play_status(guid: "ep1"),
              build_play_status(guid: "ep2")
            ]
          ),
          build_subscription(
            feed_url: "https://example.com/feed2.xml",
            play_statuses: [
              build_play_status(guid: "ep3")
            ]
          )
        ],
        playlists: [
          build_playlist(name: "Favorites")
        ],
        collections: [
          build_collection(title: "Tech Podcasts")
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc, dry_run: true)

      assert stats.subscriptions.imported == 2
      assert stats.play_statuses.imported == 3
      assert stats.playlists.imported == 1
      assert stats.collections.imported == 1

      # Verify nothing was actually created
      encoded_feed = Base.url_encode64("https://example.com/feed1.xml", padding: false)
      sub = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.Subscription, user_id: user_id, rss_source_feed: encoded_feed)
      assert sub == nil
    end
  end

  describe "playlist import" do
    test "imports new playlist", %{user_id: user_id} do
      doc = build_document(
        playlists: [
          build_playlist(
            name: "My Favorites",
            description: "Best episodes",
            type: "playlist",
            is_public: true
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.playlists.imported == 1

      playlist = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.Playlist, user_id: user_id, name: "My Favorites")
      assert playlist != nil
      assert playlist.description == "Best episodes"
      assert playlist.is_public == true
    end

    test "imports playlist with items", %{user_id: user_id} do
      doc = build_document(
        playlists: [
          build_playlist(
            name: "Queue",
            type: "queue",
            items: [
              build_playlist_item(
                feed_url: "https://example.com/feed.xml",
                guid: "episode-1",
                position: 0
              ),
              build_playlist_item(
                feed_url: "https://example.com/feed.xml",
                guid: "episode-2",
                position: 1
              )
            ]
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.playlists.imported == 1

      playlist = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.Playlist, user_id: user_id, name: "Queue")
      assert playlist != nil

      items = ProjectionsRepo.all(
        from(pi in BaladosSyncProjections.Schemas.PlaylistItem,
          where: pi.playlist_id == ^playlist.id,
          order_by: pi.position
        )
      )
      assert length(items) == 2
    end
  end

  describe "collection import" do
    test "imports new collection", %{user_id: user_id} do
      doc = build_document(
        collections: [
          build_collection(
            title: "Tech Podcasts",
            description: "All tech related",
            is_public: false,
            color: "#FF5733"
          )
        ]
      )

      {:ok, stats} = DataImporter.import(user_id, doc)

      assert stats.collections.imported == 1

      collection = ProjectionsRepo.get_by(BaladosSyncProjections.Schemas.Collection, user_id: user_id, title: "Tech Podcasts")
      assert collection != nil
      assert collection.description == "All tech related"
      assert collection.color == "#FF5733"
    end
  end

  # ===== Test Helpers =====

  defp build_document(opts) do
    %BaladosSyncWeb.Opml.Document{
      title: opts[:title] || "Test Export",
      date_created: opts[:date_created] || DateTime.utc_now(),
      version: opts[:version] || "1.0",
      subscriptions: opts[:subscriptions] || [],
      playlists: opts[:playlists] || [],
      collections: opts[:collections] || []
    }
  end

  defp build_subscription(opts) do
    %BaladosSyncWeb.Opml.Subscription{
      feed_url: opts[:feed_url],
      title: opts[:title] || "Test Podcast",
      subscribed_at: opts[:subscribed_at],
      unsubscribed_at: opts[:unsubscribed_at],
      privacy: opts[:privacy] || "public",
      source_id: opts[:source_id],
      play_statuses: opts[:play_statuses] || []
    }
  end

  defp build_play_status(opts) do
    %BaladosSyncWeb.Opml.PlayStatus{
      guid: opts[:guid] || "test-guid",
      position: opts[:position] || 0,
      played: opts[:played] || false,
      updated_at: opts[:updated_at]
    }
  end

  defp build_playlist(opts) do
    %BaladosSyncWeb.Opml.Playlist{
      id: opts[:id],
      name: opts[:name] || "Test Playlist",
      description: opts[:description],
      type: opts[:type] || "playlist",
      is_public: opts[:is_public] || false,
      updated_at: opts[:updated_at],
      items: opts[:items] || []
    }
  end

  defp build_playlist_item(opts) do
    %BaladosSyncWeb.Opml.PlaylistItem{
      feed_url: opts[:feed_url] || "https://example.com/feed.xml",
      guid: opts[:guid] || "test-guid",
      position: opts[:position] || 0,
      item_title: opts[:item_title],
      feed_title: opts[:feed_title]
    }
  end

  defp build_collection(opts) do
    %BaladosSyncWeb.Opml.Collection{
      id: opts[:id],
      title: opts[:title] || "Test Collection",
      description: opts[:description],
      is_public: opts[:is_public] || false,
      color: opts[:color],
      updated_at: opts[:updated_at],
      feeds: opts[:feeds] || []
    }
  end

  defp encode_item(feed_url, guid) do
    data = "#{feed_url},#{guid},"
    Base.url_encode64(data, padding: false)
  end
end
