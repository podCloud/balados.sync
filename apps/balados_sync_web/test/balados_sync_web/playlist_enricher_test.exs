defmodule BaladosSyncWeb.PlaylistEnricherTest do
  @moduledoc """
  Tests for PlaylistEnricher module.

  Tests the enrichment logic, formatting functions, and parallel feed fetching.
  """

  use ExUnit.Case, async: true

  alias BaladosSyncWeb.PlaylistEnricher

  describe "enrich_items/1" do
    test "returns empty list for empty input" do
      assert PlaylistEnricher.enrich_items([]) == []
    end

    test "enriches items with fallback data when feed is unreachable" do
      items = [
        %{
          id: "item-1",
          user_id: "user-1",
          playlist_id: "playlist-1",
          rss_source_feed: "https://invalid.example.com/feed.xml",
          rss_source_item: "episode-1",
          position: 1,
          item_title: "Cached Title",
          feed_title: "Cached Feed"
        }
      ]

      result = PlaylistEnricher.enrich_items(items)

      assert length(result) == 1
      [enriched] = result

      # Should use fallback data
      assert enriched.item_title == "Cached Title"
      assert enriched.feed_title == "Cached Feed"
      assert enriched.enriched == false
      assert enriched.description == nil
      assert enriched.cover == nil
    end
  end

  describe "format_duration/1" do
    test "returns nil for nil input" do
      assert PlaylistEnricher.format_duration(nil) == nil
    end

    test "returns nil for negative values" do
      assert PlaylistEnricher.format_duration(-1) == nil
    end

    test "formats seconds under a minute" do
      assert PlaylistEnricher.format_duration(45) == "0:45"
    end

    test "formats minutes and seconds" do
      assert PlaylistEnricher.format_duration(125) == "2:05"
    end

    test "formats hours, minutes, and seconds" do
      # 1 hour, 30 minutes, 45 seconds
      assert PlaylistEnricher.format_duration(5445) == "1:30:45"
    end

    test "pads single-digit minutes and seconds" do
      assert PlaylistEnricher.format_duration(3661) == "1:01:01"
    end

    test "handles zero duration" do
      assert PlaylistEnricher.format_duration(0) == "0:00"
    end
  end

  describe "format_pub_date/1" do
    test "returns nil for nil input" do
      assert PlaylistEnricher.format_pub_date(nil) == nil
    end

    test "returns 'Today' for dates from today" do
      today = DateTime.utc_now()
      assert PlaylistEnricher.format_pub_date(today) == "Today"
    end

    test "returns 'Yesterday' for dates from yesterday" do
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day)
      assert PlaylistEnricher.format_pub_date(yesterday) == "Yesterday"
    end

    test "returns 'X days ago' for recent dates" do
      three_days_ago = DateTime.utc_now() |> DateTime.add(-3, :day)
      assert PlaylistEnricher.format_pub_date(three_days_ago) == "3 days ago"
    end

    test "returns 'X weeks ago' for dates less than a month old" do
      two_weeks_ago = DateTime.utc_now() |> DateTime.add(-14, :day)
      assert PlaylistEnricher.format_pub_date(two_weeks_ago) == "2 weeks ago"
    end

    test "returns 'X months ago' for dates less than a year old" do
      three_months_ago = DateTime.utc_now() |> DateTime.add(-90, :day)
      assert PlaylistEnricher.format_pub_date(three_months_ago) == "3 months ago"
    end

    test "returns formatted date for old dates" do
      old_date = ~U[2020-06-15 12:00:00Z]
      assert PlaylistEnricher.format_pub_date(old_date) == "Jun 15, 2020"
    end
  end

  describe "strip_html_tags/1" do
    test "returns empty string for nil input" do
      assert PlaylistEnricher.strip_html_tags(nil) == ""
    end

    test "strips simple HTML tags" do
      html = "<p>Hello <strong>World</strong></p>"
      assert PlaylistEnricher.strip_html_tags(html) == "Hello World"
    end

    test "strips multiple tags and normalizes whitespace" do
      html = """
      <div>
        <p>First paragraph</p>
        <p>Second paragraph</p>
      </div>
      """

      result = PlaylistEnricher.strip_html_tags(html)
      assert result == "First paragraph Second paragraph"
    end

    test "handles tags with attributes" do
      html = "<a href=\"https://example.com\" class=\"link\">Click here</a>"
      assert PlaylistEnricher.strip_html_tags(html) == "Click here"
    end

    test "handles empty input" do
      assert PlaylistEnricher.strip_html_tags("") == ""
    end

    test "handles text without HTML" do
      text = "Plain text without any tags"
      assert PlaylistEnricher.strip_html_tags(text) == "Plain text without any tags"
    end

    test "handles self-closing tags" do
      html = "Line 1<br/>Line 2<br />Line 3"
      assert PlaylistEnricher.strip_html_tags(html) == "Line 1 Line 2 Line 3"
    end
  end

  describe "fetch_feeds_parallel/1" do
    test "returns empty map for empty input" do
      assert PlaylistEnricher.fetch_feeds_parallel([]) == %{}
    end

    test "handles invalid URLs gracefully" do
      result = PlaylistEnricher.fetch_feeds_parallel(["https://invalid.example.com/feed.xml"])
      # Should return empty map or map with empty episodes for failed fetch
      assert is_map(result)
    end
  end
end
