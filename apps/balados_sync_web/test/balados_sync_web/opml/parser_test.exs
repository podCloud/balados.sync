defmodule BaladosSyncWeb.Opml.ParserTest do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.Opml.Parser

  describe "parse/1 with standard OPML" do
    test "parses basic OPML 2.0 with subscriptions" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
        <head>
          <title>My Subscriptions</title>
        </head>
        <body>
          <outline type="rss" text="Test Podcast" xmlUrl="https://example.com/feed.xml"/>
          <outline type="rss" text="Another Podcast" xmlUrl="https://other.com/feed.xml"/>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      assert length(doc.subscriptions) == 2

      [sub1, sub2] = doc.subscriptions
      assert sub1.title == "Test Podcast"
      assert sub1.feed_url == "https://example.com/feed.xml"
      assert sub2.title == "Another Podcast"
      assert sub2.feed_url == "https://other.com/feed.xml"
    end

    test "handles nested outline groups" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
        <head><title>Subscriptions</title></head>
        <body>
          <outline text="Tech">
            <outline type="rss" text="Tech Pod 1" xmlUrl="https://tech1.com/feed.xml"/>
            <outline type="rss" text="Tech Pod 2" xmlUrl="https://tech2.com/feed.xml"/>
          </outline>
          <outline text="News">
            <outline type="rss" text="News Pod" xmlUrl="https://news.com/feed.xml"/>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      assert length(doc.subscriptions) == 3
    end

    test "returns error for invalid XML" do
      assert {:error, :xml_parse_failed} = Parser.parse("<invalid>not closed")
    end

    test "returns empty document for non-OPML XML" do
      # Parser is permissive - returns empty document for non-OPML
      assert {:ok, doc} = Parser.parse("<html><body>Hello</body></html>")
      assert doc.subscriptions == []
      assert doc.playlists == []
      assert doc.collections == []
    end
  end

  describe "parse/1 with extended OPML (balados namespace)" do
    test "parses subscription dates and privacy" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
        <head>
          <title>Export</title>
          <balados:version>1.0</balados:version>
        </head>
        <body>
          <outline text="Subscriptions">
            <outline type="rss"
                     text="Test Podcast"
                     xmlUrl="https://example.com/feed.xml"
                     balados:subscribedAt="Sun, 15 Dec 2025 10:30:00 GMT"
                     balados:privacy="anonymous"
                     balados:sourceId="abc123"/>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      assert length(doc.subscriptions) == 1

      [sub] = doc.subscriptions
      assert sub.title == "Test Podcast"
      assert sub.feed_url == "https://example.com/feed.xml"
      assert sub.privacy == "anonymous"
      assert sub.source_id == "abc123"
      assert %DateTime{} = sub.subscribed_at
    end

    test "parses play statuses nested in subscriptions" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
        <head><title>Export</title></head>
        <body>
          <outline text="Subscriptions">
            <outline type="rss" text="Test Podcast" xmlUrl="https://example.com/feed.xml">
              <outline balados:type="playStatus"
                       balados:guid="episode-123"
                       balados:position="1845"
                       balados:played="false"
                       balados:updatedAt="Sat, 11 Jan 2026 15:30:00 GMT"/>
              <outline balados:type="playStatus"
                       balados:guid="episode-456"
                       balados:position="3600"
                       balados:played="true"/>
            </outline>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      [sub] = doc.subscriptions
      assert length(sub.play_statuses) == 2

      [ps1, ps2] = sub.play_statuses
      assert ps1.guid == "episode-123"
      assert ps1.position == 1845
      assert ps1.played == false

      assert ps2.guid == "episode-456"
      assert ps2.position == 3600
      assert ps2.played == true
    end

    test "parses playlists section" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
        <head><title>Export</title></head>
        <body>
          <outline text="Playlists" balados:type="playlists">
            <outline balados:type="playlist"
                     balados:id="pl-123"
                     balados:name="Road Trip"
                     balados:description="Long episodes"
                     balados:playlistType="playlist"
                     balados:isPublic="true"
                     balados:updatedAt="Sat, 11 Jan 2026 12:00:00 GMT">
              <outline balados:type="playlistItem"
                       balados:feedUrl="https://example.com/feed.xml"
                       balados:guid="ep-1"
                       balados:position="0"
                       balados:itemTitle="Episode One"
                       balados:feedTitle="Test Podcast"/>
            </outline>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      assert length(doc.playlists) == 1

      [playlist] = doc.playlists
      assert playlist.id == "pl-123"
      assert playlist.name == "Road Trip"
      assert playlist.description == "Long episodes"
      assert playlist.type == "playlist"
      assert playlist.is_public == true
      assert length(playlist.items) == 1

      [item] = playlist.items
      assert item.feed_url == "https://example.com/feed.xml"
      assert item.guid == "ep-1"
      assert item.position == 0
      assert item.item_title == "Episode One"
    end

    test "parses collections section" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
        <head><title>Export</title></head>
        <body>
          <outline text="Collections" balados:type="collections">
            <outline balados:type="collection"
                     balados:id="coll-123"
                     balados:title="Tech Podcasts"
                     balados:description="My tech shows"
                     balados:isPublic="false"
                     balados:color="#3B82F6">
              <outline balados:type="collectionFeed"
                       balados:feedUrl="https://example.com/feed1.xml"/>
              <outline balados:type="collectionFeed"
                       balados:feedUrl="https://example.com/feed2.xml"/>
            </outline>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      assert length(doc.collections) == 1

      [coll] = doc.collections
      assert coll.id == "coll-123"
      assert coll.title == "Tech Podcasts"
      assert coll.description == "My tech shows"
      assert coll.is_public == false
      assert coll.color == "#3B82F6"
      assert length(coll.feeds) == 2
      assert "https://example.com/feed1.xml" in coll.feeds
      assert "https://example.com/feed2.xml" in coll.feeds
    end
  end

  describe "parse/1 date parsing" do
    test "parses RFC 822 dates" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
        <head><title>Export</title></head>
        <body>
          <outline text="Subscriptions">
            <outline type="rss" text="Test" xmlUrl="https://example.com/feed.xml"
                     balados:subscribedAt="Sun, 15 Dec 2025 10:30:00 GMT"/>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      [sub] = doc.subscriptions
      assert sub.subscribed_at.year == 2025
      assert sub.subscribed_at.month == 12
      assert sub.subscribed_at.day == 15
    end

    test "handles ISO 8601 dates as fallback" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
        <head><title>Export</title></head>
        <body>
          <outline text="Subscriptions">
            <outline type="rss" text="Test" xmlUrl="https://example.com/feed.xml"
                     balados:subscribedAt="2025-12-15T10:30:00Z"/>
          </outline>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      [sub] = doc.subscriptions
      assert sub.subscribed_at.year == 2025
    end
  end

  describe "parse/1 special characters" do
    test "handles XML-escaped characters in titles" do
      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
        <head><title>Export</title></head>
        <body>
          <outline type="rss" text="Test &amp; Podcast &lt;with&gt; &quot;special&quot;" xmlUrl="https://example.com/feed.xml"/>
        </body>
      </opml>
      """

      assert {:ok, doc} = Parser.parse(opml)
      [sub] = doc.subscriptions
      assert sub.title == "Test & Podcast <with> \"special\""
    end
  end
end
