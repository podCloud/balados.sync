defmodule BaladosSyncWeb.Opml.BuilderTest do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.Opml.Builder

  alias BaladosSyncWeb.Opml.{
    Document,
    Subscription,
    PlayStatus,
    Playlist,
    PlaylistItem,
    Collection
  }

  @test_user %{username: "testuser"}

  describe "build/3 with standard format" do
    test "generates valid OPML 2.0 for empty document" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :standard)

      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert xml =~ ~s(<opml version="2.0">)
      assert xml =~ ~s(<title>testuser - Balados Sync Subscriptions</title>)
      refute xml =~ "balados:"
    end

    test "generates subscription outlines" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [
          %Subscription{
            feed_url: "https://example.com/feed.xml",
            title: "Test Podcast",
            subscribed_at: DateTime.utc_now(),
            privacy: "public",
            play_statuses: []
          }
        ],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :standard)

      assert xml =~ ~s(type="rss")
      assert xml =~ ~s(text="Test Podcast")
      assert xml =~ ~s(xmlUrl="https://example.com/feed.xml")
    end

    test "escapes special XML characters in titles" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [
          %Subscription{
            feed_url: "https://example.com/feed.xml",
            title: "Test & Podcast <with> \"special\" 'chars'",
            subscribed_at: DateTime.utc_now(),
            privacy: "public",
            play_statuses: []
          }
        ],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :standard)

      assert xml =~ "&amp;"
      assert xml =~ "&lt;"
      assert xml =~ "&gt;"
      assert xml =~ "&quot;"
      assert xml =~ "&apos;"
    end
  end

  describe "build/3 with extended format" do
    test "includes balados namespace" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :extended)

      assert xml =~ ~s(xmlns:balados="https://balados.sync/opml/1.0")
      assert xml =~ "balados:version"
    end

    test "includes subscription dates and privacy" do
      subscribed_at = ~U[2025-12-15 10:30:00Z]

      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [
          %Subscription{
            feed_url: "https://example.com/feed.xml",
            title: "Test Podcast",
            subscribed_at: subscribed_at,
            privacy: "anonymous",
            source_id: "abc123",
            play_statuses: []
          }
        ],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :extended)

      assert xml =~ "balados:subscribedAt="
      assert xml =~ ~s(balados:privacy="anonymous")
      assert xml =~ ~s(balados:sourceId="abc123")
    end

    test "includes play statuses nested in subscriptions" do
      updated_at = ~U[2025-12-15 10:30:00Z]

      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [
          %Subscription{
            feed_url: "https://example.com/feed.xml",
            title: "Test Podcast",
            subscribed_at: DateTime.utc_now(),
            privacy: "public",
            play_statuses: [
              %PlayStatus{
                guid: "episode-123",
                position: 1845,
                played: false,
                updated_at: updated_at
              }
            ]
          }
        ],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :extended)

      assert xml =~ ~s(balados:type="playStatus")
      assert xml =~ ~s(balados:guid="episode-123")
      assert xml =~ ~s(balados:position="1845")
      assert xml =~ ~s(balados:played="false")
    end

    test "includes playlists section" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [],
        playlists: [
          %Playlist{
            id: "playlist-1",
            name: "Road Trip",
            description: "Long episodes",
            type: "playlist",
            is_public: true,
            updated_at: DateTime.utc_now(),
            items: [
              %PlaylistItem{
                feed_url: "https://example.com/feed.xml",
                guid: "episode-456",
                position: 0,
                item_title: "Episode One",
                feed_title: "Test Podcast"
              }
            ]
          }
        ],
        collections: []
      }

      xml = Builder.build(doc, @test_user, format: :extended)

      assert xml =~ ~s(balados:type="playlists")
      assert xml =~ ~s(balados:type="playlist")
      assert xml =~ ~s(balados:name="Road Trip")
      assert xml =~ ~s(balados:isPublic="true")
      assert xml =~ ~s(balados:type="playlistItem")
      assert xml =~ ~s(balados:feedUrl="https://example.com/feed.xml")
      assert xml =~ ~s(balados:guid="episode-456")
    end

    test "includes collections section" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [],
        playlists: [],
        collections: [
          %Collection{
            id: "coll-1",
            title: "Tech Podcasts",
            description: "My tech shows",
            is_public: false,
            color: "#3B82F6",
            updated_at: DateTime.utc_now(),
            feeds: [
              "https://example.com/feed1.xml",
              "https://example.com/feed2.xml"
            ]
          }
        ]
      }

      xml = Builder.build(doc, @test_user, format: :extended)

      assert xml =~ ~s(balados:type="collections")
      assert xml =~ ~s(balados:type="collection")
      assert xml =~ ~s(balados:title="Tech Podcasts")
      assert xml =~ ~s(balados:color="#3B82F6")
      assert xml =~ ~s(balados:type="collectionFeed")
      assert xml =~ ~s(balados:feedUrl="https://example.com/feed1.xml")
    end
  end

  describe "build/3 defaults" do
    test "defaults to extended format" do
      doc = %Document{
        title: nil,
        date_created: DateTime.utc_now(),
        version: "1.0",
        subscriptions: [],
        playlists: [],
        collections: []
      }

      xml = Builder.build(doc, @test_user)

      assert xml =~ "balados:"
    end
  end
end
