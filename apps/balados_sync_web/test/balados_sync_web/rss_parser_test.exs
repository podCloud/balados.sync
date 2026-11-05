defmodule BaladosSyncWeb.RssParserTest do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.RssParser

  defp feed_with_pub_date(pub_date) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Test</title>
        <item>
          <guid>episode-1</guid>
          <title>Episode 1</title>
          <pubDate>#{pub_date}</pubDate>
          <enclosure url="https://example.com/e1.mp3" type="audio/mpeg" length="1" />
        </item>
      </channel>
    </rss>
    """
  end

  describe "parse_episodes/1 with RFC 2822 pubDate" do
    test "converts a positive numeric offset to UTC" do
      assert {:ok, [episode]} =
               RssParser.parse_episodes(feed_with_pub_date("Mon, 03 Nov 2025 10:00:00 +0530"))

      assert DateTime.compare(episode.pub_date, ~U[2025-11-03 04:30:00Z]) == :eq
    end

    test "converts a negative numeric offset to UTC" do
      assert {:ok, [episode]} =
               RssParser.parse_episodes(feed_with_pub_date("Mon, 03 Nov 2025 10:00:00 -0500"))

      assert DateTime.compare(episode.pub_date, ~U[2025-11-03 15:00:00Z]) == :eq
    end

    test "keeps +0000 unchanged" do
      assert {:ok, [episode]} =
               RssParser.parse_episodes(feed_with_pub_date("Mon, 03 Nov 2025 10:00:00 +0000"))

      assert DateTime.compare(episode.pub_date, ~U[2025-11-03 10:00:00Z]) == :eq
    end
  end
end
