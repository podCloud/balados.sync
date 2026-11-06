defmodule BaladosSyncWeb.Plugs.RateLimiterTest do
  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncWeb.Plugs.RateLimiter

  describe "init/1" do
    test "requires limit option" do
      assert_raise KeyError, fn ->
        RateLimiter.init(window_ms: 1000, key: :ip)
      end
    end

    test "requires window_ms option" do
      assert_raise KeyError, fn ->
        RateLimiter.init(limit: 10, key: :ip)
      end
    end

    test "requires key option" do
      assert_raise KeyError, fn ->
        RateLimiter.init(limit: 10, window_ms: 1000)
      end
    end

    test "returns opts map with defaults" do
      opts = RateLimiter.init(limit: 10, window_ms: 1000, key: :ip)
      assert opts.limit == 10
      assert opts.window_ms == 1000
      assert opts.key == :ip
      assert opts.namespace == "rate_limiter"
      assert is_function(opts.skip, 1)
    end
  end

  describe "call/2 limit and Retry-After" do
    test "second request with limit: 1 gets 429 with a Retry-After within the window" do
      opts = RateLimiter.init(limit: 1, window_ms: 60_000, key: :ip, namespace: "test_limit_one")
      BaladosSyncWeb.RateLimit.reset()

      first =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      refute first.halted

      second =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      assert second.halted
      assert second.status == 429
      [retry_after] = Plug.Conn.get_resp_header(second, "retry-after")
      retry_after = String.to_integer(retry_after)
      assert retry_after >= 1 and retry_after <= 60
      assert Jason.decode!(second.resp_body)["retry_after_seconds"] == retry_after
    end

    test "Retry-After is bounded by the window" do
      opts = RateLimiter.init(limit: 1, window_ms: 2_000, key: :ip, namespace: "test_bounded")
      BaladosSyncWeb.RateLimit.reset()
      conn = build_conn(:get, "/test") |> Map.put(:remote_ip, {127, 0, 0, 1})
      refute RateLimiter.call(conn, opts).halted
      [first] = RateLimiter.call(conn, opts) |> Plug.Conn.get_resp_header("retry-after")
      assert String.to_integer(first) <= 2
    end
  end

  describe "call/2 with :ip key" do
    test "allows requests under the limit" do
      opts = RateLimiter.init(limit: 5, window_ms: 60_000, key: :ip, namespace: "test_ip")

      # Clear any previous rate limit data
      BaladosSyncWeb.RateLimit.reset()

      conn =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      refute conn.halted
    end

    test "blocks requests over the limit" do
      opts = RateLimiter.init(limit: 2, window_ms: 60_000, key: :ip, namespace: "test_over_limit")

      # Clear any previous rate limit data
      BaladosSyncWeb.RateLimit.reset()

      # Make requests up to the limit
      conn1 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      refute conn1.halted

      conn2 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      refute conn2.halted

      # Third request should be blocked
      conn3 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      assert conn3.halted
      assert conn3.status == 429
      # Hammer 7 fixed windows are aligned on the wall clock: the header carries
      # the seconds left in the current window, not the whole window.
      [retry_after] = get_resp_header(conn3, "retry-after")
      assert String.to_integer(retry_after) in 1..60

      body = Jason.decode!(conn3.resp_body)
      assert body["error"] == "RATE_LIMIT_EXCEEDED"
    end

    test "uses x-forwarded-for header when present" do
      opts = RateLimiter.init(limit: 1, window_ms: 60_000, key: :ip, namespace: "test_xff")

      # Clear any previous rate limit data
      BaladosSyncWeb.RateLimit.reset()

      conn =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "192.168.1.100, 10.0.0.1")
        |> RateLimiter.call(opts)

      refute conn.halted

      # Second request from same forwarded IP should be blocked
      conn2 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "192.168.1.100, 10.0.0.1")
        |> RateLimiter.call(opts)

      assert conn2.halted
    end
  end

  describe "call/2 with :user_id key" do
    test "skips rate limiting when no user_id present" do
      opts = RateLimiter.init(limit: 1, window_ms: 60_000, key: :user_id, namespace: "test_user")

      conn =
        build_conn(:get, "/test")
        |> RateLimiter.call(opts)

      refute conn.halted
    end

    test "rate limits by user_id when present" do
      opts =
        RateLimiter.init(limit: 1, window_ms: 60_000, key: :user_id, namespace: "test_user_limit")

      user_id = Ecto.UUID.generate()

      # Clear any previous rate limit data
      BaladosSyncWeb.RateLimit.reset()

      conn1 =
        build_conn(:get, "/test")
        |> assign(:current_user_id, user_id)
        |> RateLimiter.call(opts)

      refute conn1.halted

      # Second request should be blocked
      conn2 =
        build_conn(:get, "/test")
        |> assign(:current_user_id, user_id)
        |> RateLimiter.call(opts)

      assert conn2.halted
      assert conn2.status == 429
    end
  end

  describe "call/2 with {:param, name} key" do
    test "uses param value as key" do
      opts =
        RateLimiter.init(
          limit: 1,
          window_ms: 60_000,
          key: {:param, "token"},
          namespace: "test_param"
        )

      # Clear any previous rate limit data
      BaladosSyncWeb.RateLimit.reset()

      conn1 =
        build_conn(:get, "/test", %{"token" => "my_token"})
        |> RateLimiter.call(opts)

      refute conn1.halted

      # Second request with same token should be blocked
      conn2 =
        build_conn(:get, "/test", %{"token" => "my_token"})
        |> RateLimiter.call(opts)

      assert conn2.halted

      # Different token should not be blocked
      BaladosSyncWeb.RateLimit.reset()

      conn3 =
        build_conn(:get, "/test", %{"token" => "other_token"})
        |> RateLimiter.call(opts)

      refute conn3.halted
    end

    test "skips when param is missing" do
      opts =
        RateLimiter.init(
          limit: 1,
          window_ms: 60_000,
          key: {:param, "missing"},
          namespace: "test_missing"
        )

      # Build conn with empty params (not unfetched)
      conn =
        build_conn(:get, "/test", %{})
        |> RateLimiter.call(opts)

      refute conn.halted
    end
  end

  describe "call/2 with skip option" do
    test "skips rate limiting when skip function returns true" do
      skip_fn = fn conn -> conn.assigns[:skip_rate_limit] == true end

      opts =
        RateLimiter.init(
          limit: 1,
          window_ms: 60_000,
          key: :ip,
          namespace: "test_skip",
          skip: skip_fn
        )

      # First request without skip
      BaladosSyncWeb.RateLimit.reset()

      conn1 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      refute conn1.halted

      # Second request without skip should be blocked
      conn2 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimiter.call(opts)

      assert conn2.halted

      # Third request with skip should not be blocked
      conn3 =
        build_conn(:get, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> assign(:skip_rate_limit, true)
        |> RateLimiter.call(opts)

      refute conn3.halted
    end
  end
end
