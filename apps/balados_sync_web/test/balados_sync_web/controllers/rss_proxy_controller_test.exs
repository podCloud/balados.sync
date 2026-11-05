defmodule BaladosSyncWeb.RssProxyControllerTest do
  use BaladosSyncWeb.ConnCase

  @moduletag :rss_proxy_controller

  alias BaladosSyncWeb.JwtTestHelper

  setup %{conn: conn} do
    user_id = Ecto.UUID.generate()
    authed = JwtTestHelper.authenticate_conn(conn, user_id, scopes: ["user.sync"])
    {:ok, conn: authed, anon_conn: conn, user_id: user_id}
  end

  # Helper to encode feed URLs (padded form; the unpadded contract form is tested separately)
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

  describe "GET /api/v1/rss/proxy - blocked URLs and caching" do
    test "returns 400 when the feed URL is rejected by the SSRF validator", %{conn: conn} do
      conn = get(conn, "/api/v1/rss/proxy/#{encode_feed("http://127.0.0.1/feed.xml")}")
      assert json_response(conn, 400)["error"] == "BAD_REQUEST"
    end

    test "returns 400 on the episode route when the feed URL is rejected", %{conn: conn} do
      conn =
        get(
          conn,
          "/api/v1/rss/proxy/#{encode_feed("not a url")}/#{encode_episode("g", "https://example.com/e.mp3")}"
        )

      assert json_response(conn, 400)["error"] == "BAD_REQUEST"
    end

    test "serves a cached feed with private cache-control and CORS on both routes", %{conn: conn} do
      # Seed the cache so no network call happens; the cache is checked first.
      feed_url = "https://cached.example.com/feed.xml"

      xml =
        ~s(<rss><channel><item><guid>g1</guid><enclosure url="https://cached.example.com/e.mp3"/></item></channel></rss>)

      BaladosSyncCore.RssCache.put({:feed, feed_url}, xml)

      conn_feed = get(conn, "/api/v1/rss/proxy/#{encode_feed(feed_url)}")
      assert response(conn_feed, 200) == xml
      assert get_resp_header(conn_feed, "cache-control") == ["private, max-age=300"]
      assert get_resp_header(conn_feed, "access-control-allow-origin") == ["*"]

      conn_ep =
        get(
          conn,
          "/api/v1/rss/proxy/#{encode_feed(feed_url)}/#{encode_episode("g1", "https://cached.example.com/e.mp3")}"
        )

      assert response(conn_ep, 200) == xml
      assert get_resp_header(conn_ep, "cache-control") == ["private, max-age=300"]
    end
  end

  describe "CORS (the app calls the proxy cross-origin with an Authorization header)" do
    test "answers the preflight with the allowed headers", %{anon_conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://app.example.com")
        |> put_req_header("access-control-request-method", "GET")
        |> put_req_header("access-control-request-headers", "authorization")
        |> options("/api/v1/rss/proxy/#{encode_feed("https://example.com/feed.xml")}")

      assert conn.status == 204
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert [headers] = get_resp_header(conn, "access-control-allow-headers")
      assert headers =~ ~r/authorization/i
      assert [methods] = get_resp_header(conn, "access-control-allow-methods")
      assert methods =~ "GET"
    end

    test "exposes the origin header on error responses so the app can read the status", %{
      anon_conn: conn
    } do
      conn =
        conn
        |> put_req_header("origin", "https://app.example.com")
        |> get("/api/v1/rss/proxy/#{encode_feed("https://example.com/feed.xml")}")

      assert conn.status == 401
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert [exposed] = get_resp_header(conn, "access-control-expose-headers")
      assert exposed =~ ~r/retry-after/i
    end

    test "does not touch non-API routes", %{anon_conn: conn} do
      conn = conn |> put_req_header("origin", "https://app.example.com") |> get("/")
      assert get_resp_header(conn, "access-control-allow-origin") == []
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

    test "accepts unpadded base64url ids (the API contract)", %{conn: conn} do
      # A URL whose encoding contains url-safe characters, so the standard
      # base64 fallback cannot rescue it; the loopback host is rejected by the
      # SSRF validator before any network call.
      unpadded = Base.url_encode64("http://127.0.0.1/feed.xml?b=~~~", padding: false)
      refute String.ends_with?(unpadded, "=")
      assert unpadded =~ ~r/[-_]/

      conn = get(conn, "/api/v1/rss/proxy/#{unpadded}")

      assert json_response(conn, 400)["message"] == "Feed URL not allowed"
    end

    test "accepts standard base64 encoding (backwards compatibility)", %{conn: conn} do
      # Standard base64 with padding
      encoded = Base.encode64("https://example.com/feed.xml")
      conn = get(conn, "/api/v1/rss/proxy/#{URI.encode(encoded)}")

      # Should decode OK but fail on fetch, not on decoding
      assert json_response(conn, 502)["error"] == "BAD_GATEWAY"
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
      assert json_response(conn, 400)["error"] == "BAD_REQUEST"
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
