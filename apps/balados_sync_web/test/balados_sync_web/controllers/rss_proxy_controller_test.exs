defmodule BaladosSyncWeb.RssProxyControllerTest do
  use BaladosSyncWeb.ConnCase

  @moduletag :rss_proxy_controller

  alias BaladosSyncWeb.JwtTestHelper

  setup %{conn: conn} do
    user_id = Ecto.UUID.generate()
    authed = JwtTestHelper.authenticate_conn(conn, user_id, scopes: ["user.sync"])
    {:ok, conn: authed, anon_conn: conn, user_id: user_id}
  end

  # Helper to encode feed URLs with padding (required by the controller's url_decode64)
  defp encode_feed(url), do: Base.url_encode64(url)

  # Helper to encode episode IDs
  defp encode_episode(guid, enclosure), do: Base.url_encode64("#{guid},#{enclosure}")

  describe "GET /api/v1/rss/proxy - authentication" do
    test "returns 401 without JWT", %{anon_conn: conn} do
      conn = get(conn, "/api/v1/rss/proxy/#{encode_feed("https://example.com/feed.xml")}")
      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "returns 401 on the episode route without JWT", %{anon_conn: conn} do
      conn =
        get(
          conn,
          "/api/v1/rss/proxy/#{encode_feed("https://example.com/feed.xml")}/#{encode_episode("g", "https://example.com/e.mp3")}"
        )

      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "returns 403 with a JWT lacking a sync or subscriptions scope", %{
      anon_conn: conn,
      user_id: user_id
    } do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.read"])
        |> get("/api/v1/rss/proxy/#{encode_feed("https://example.com/feed.xml")}")

      assert json_response(conn, 403)
    end

    test "proceeds past auth with user.subscriptions.read scope", %{
      anon_conn: conn,
      user_id: user_id
    } do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.subscriptions.read"])
        |> get("/api/v1/rss/proxy/#{encode_feed("https://example.com/nonexistent-feed.xml")}")

      assert json_response(conn, 502)["error"] == "BAD_GATEWAY"
    end

    test "proceeds past auth with user.sync scope", %{conn: conn} do
      conn =
        get(conn, "/api/v1/rss/proxy/#{encode_feed("https://example.com/nonexistent-feed.xml")}")

      assert json_response(conn, 502)["error"] == "BAD_GATEWAY"
    end
  end

  describe "GET /api/v1/rss/proxy - rate limiting" do
    # The plug runs before the action, so an invalid feed id (400, no network
    # call) is enough to consume quota. Buckets are reset first so the test does
    # not depend on what ran before it.
    @quota_path "/api/v1/rss/proxy/!!!not-base64!!!"

    setup %{user_id: user_id} do
      Hammer.delete_buckets("rss_proxy:user:#{user_id}")
      :ok
    end

    test "returns 429 with Retry-After after 120 requests in a minute", %{conn: conn} do
      for _ <- 1..120, do: assert(get(conn, @quota_path).status == 400)

      conn = get(conn, @quota_path)

      assert json_response(conn, 429)
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
    end

    test "quota is shared across devices of the same user", %{anon_conn: conn, user_id: user_id} do
      device_a =
        JwtTestHelper.authenticate_conn(conn, user_id, scopes: ["user.sync"], device_id: "a")

      device_b =
        JwtTestHelper.authenticate_conn(conn, user_id, scopes: ["user.sync"], device_id: "b")

      for _ <- 1..120, do: get(device_a, @quota_path)

      conn = get(device_b, @quota_path)

      assert json_response(conn, 429)
    end

    test "quota is per user", %{anon_conn: conn, user_id: user_id} do
      other = JwtTestHelper.authenticate_conn(conn, Ecto.UUID.generate(), scopes: ["user.sync"])
      me = JwtTestHelper.authenticate_conn(conn, user_id, scopes: ["user.sync"])
      for _ <- 1..120, do: get(me, @quota_path)

      assert get(other, @quota_path).status == 400
    end
  end

  describe "GET /api/v1/rss/proxy/:encoded_feed_id - input validation" do
    test "returns 400 for invalid base64 encoding", %{conn: conn} do
      conn = get(conn, "/api/v1/rss/proxy/!!!not-valid-base64!!!")

      response = json_response(conn, 400)
      assert response["error"] == "BAD_REQUEST"
      assert response["message"] == "Invalid feed ID encoding"
    end

    test "returns error for non-existent feed URL", %{conn: conn} do
      encoded = encode_feed("https://example.com/nonexistent-feed.xml")
      conn = get(conn, "/api/v1/rss/proxy/#{encoded}")

      # RssCache.fetch_feed returns {:error, :fetch_failed} for unreachable feeds
      response = json_response(conn, 502)
      assert response["error"] == "BAD_GATEWAY"
      assert response["message"] == "Failed to fetch RSS feed"
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

      assert json_response(conn, 400)["error"] == "BAD_REQUEST"
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

      assert json_response(conn, 502)["error"] == "BAD_GATEWAY"
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
