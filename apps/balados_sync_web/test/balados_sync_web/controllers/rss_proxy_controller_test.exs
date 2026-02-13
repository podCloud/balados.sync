defmodule BaladosSyncWeb.RssProxyControllerTest do
  use BaladosSyncWeb.ConnCase

  @moduletag :rss_proxy_controller

  # Helper to encode feed URLs with padding (required by the controller's url_decode64)
  defp encode_feed(url), do: Base.url_encode64(url)

  # Helper to encode episode IDs
  defp encode_episode(guid, enclosure), do: Base.url_encode64("#{guid},#{enclosure}")

  describe "GET /api/v1/rss/proxy/:encoded_feed_id - input validation" do
    test "returns 400 for invalid base64 encoding", %{conn: conn} do
      conn = get(conn, "/api/v1/rss/proxy/!!!not-valid-base64!!!")

      response = json_response(conn, 400)
      assert response["error"] == "Invalid feed ID encoding"
    end

    test "returns error for non-existent feed URL", %{conn: conn} do
      encoded = encode_feed("https://example.com/nonexistent-feed.xml")
      conn = get(conn, "/api/v1/rss/proxy/#{encoded}")

      # RssCache.fetch_feed returns {:error, :fetch_failed} for unreachable feeds
      response = json_response(conn, 502)
      assert response["error"] == "Failed to fetch RSS feed"
    end

    test "accepts standard base64 encoding (backwards compatibility)", %{conn: conn} do
      # Standard base64 with padding
      encoded = Base.encode64("https://example.com/feed.xml")
      conn = get(conn, "/api/v1/rss/proxy/#{URI.encode(encoded)}")

      # Should decode OK but fail on fetch, not on decoding
      assert conn.status in [500, 502]
    end
  end

  describe "GET /api/v1/rss/proxy/:encoded_feed_id/:encoded_episode_id - input validation" do
    test "returns error for invalid feed base64", %{conn: conn} do
      episode_encoded = encode_episode("guid1", "https://example.com/ep.mp3")
      conn = get(conn, "/api/v1/rss/proxy/!!!invalid!!!/#{episode_encoded}")

      # Invalid base64 for feed causes error
      assert conn.status >= 400
      response = json_response(conn, conn.status)
      assert is_binary(response["error"])
    end

    test "returns error for invalid episode base64", %{conn: conn} do
      feed_encoded = encode_feed("https://example.com/feed.xml")
      conn = get(conn, "/api/v1/rss/proxy/#{feed_encoded}/!!!invalid!!!")

      # Feed decoding succeeds but either episode decoding or fetch fails
      assert conn.status >= 400
    end

    test "returns error when feed URL is unreachable", %{conn: conn} do
      feed_encoded = encode_feed("https://example.com/nonexistent.xml")
      episode_encoded = encode_episode("guid123", "https://example.com/ep.mp3")
      conn = get(conn, "/api/v1/rss/proxy/#{feed_encoded}/#{episode_encoded}")

      assert conn.status in [500, 502]
    end
  end

  describe "response format" do
    test "error responses return JSON content type", %{conn: conn} do
      conn = get(conn, "/api/v1/rss/proxy/!!!invalid!!!")

      content_type = get_resp_header(conn, "content-type") |> List.first()
      assert content_type =~ "application/json"
    end
  end
end
