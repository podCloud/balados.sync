defmodule BaladosSyncWeb.Plugs.RateLimiter do
  @moduledoc """
  Reusable rate limiting plug using Hammer.

  This plug provides configurable rate limiting for HTTP endpoints with support for
  different rate limit strategies (per-user, per-IP) and proper 429 responses.

  ## Usage

  In your controller or router:

      # Per-user rate limiting (requires authenticated user)
      plug BaladosSyncWeb.Plugs.RateLimiter,
        limit: 30,
        window_ms: 60_000,
        key: :user_id

      # Per-IP rate limiting (for unauthenticated endpoints)
      plug BaladosSyncWeb.Plugs.RateLimiter,
        limit: 10,
        window_ms: 60_000,
        key: :ip

      # Custom key function
      plug BaladosSyncWeb.Plugs.RateLimiter,
        limit: 100,
        window_ms: 60_000,
        key: fn conn -> conn.assigns[:custom_id] end

  ## Options

  - `:limit` - Maximum number of requests allowed (required)
  - `:window_ms` - Time window in milliseconds (required)
  - `:key` - How to identify the client. Can be:
    - `:user_id` - Uses `conn.assigns.current_user_id`
    - `:ip` - Uses client IP address
    - `:app_id` - Uses `conn.assigns.app_id`
    - `{:param, "name"}` - Uses `conn.params["name"]`
    - `{module, function}` - Calls `module.function(conn)` for custom keys
  - `:namespace` - Hammer bucket namespace (default: module name)
  - `:skip` - A function `(conn) -> boolean` to skip rate limiting (optional)

  ## Response

  When rate limited, returns a 429 Too Many Requests response with:
  - `Retry-After` header indicating seconds until limit resets
  - JSON body with error details
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @impl Plug
  def init(opts) do
    limit = Keyword.fetch!(opts, :limit)
    window_ms = Keyword.fetch!(opts, :window_ms)
    key = Keyword.fetch!(opts, :key)
    namespace = Keyword.get(opts, :namespace, "rate_limiter")
    skip = Keyword.get(opts, :skip, fn _ -> false end)

    %{
      limit: limit,
      window_ms: window_ms,
      key: key,
      namespace: namespace,
      skip: skip
    }
  end

  @impl Plug
  def call(conn, opts) do
    if opts.skip.(conn) do
      conn
    else
      case extract_key(conn, opts.key) do
        {:ok, key} ->
          check_rate_limit(conn, key, opts)

        {:error, :no_key} ->
          # No key available (e.g., unauthenticated user for :user_id key)
          # Skip rate limiting or use fallback
          conn
      end
    end
  end

  defp extract_key(conn, :user_id) do
    case conn.assigns[:current_user_id] do
      nil -> {:error, :no_key}
      user_id -> {:ok, "user:#{user_id}"}
    end
  end

  defp extract_key(conn, :ip) do
    ip = get_client_ip(conn)
    {:ok, "ip:#{ip}"}
  end

  defp extract_key(conn, :app_id) do
    case conn.assigns[:app_id] do
      nil -> {:error, :no_key}
      app_id -> {:ok, "app:#{app_id}"}
    end
  end

  defp extract_key(conn, {:param, param_name}) when is_binary(param_name) do
    case conn.params[param_name] do
      nil -> {:error, :no_key}
      value -> {:ok, "param:#{value}"}
    end
  end

  defp extract_key(conn, {module, function}) when is_atom(module) and is_atom(function) do
    case apply(module, function, [conn]) do
      nil -> {:error, :no_key}
      key -> {:ok, "custom:#{key}"}
    end
  end

  defp extract_key(conn, key_fn) when is_function(key_fn, 1) do
    case key_fn.(conn) do
      nil -> {:error, :no_key}
      key -> {:ok, "custom:#{key}"}
    end
  end

  defp get_client_ip(conn) do
    # Check for forwarded headers (proxy/load balancer)
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    case forwarded_for do
      nil ->
        # Use direct connection IP
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()

      header ->
        # Get first IP from forwarded chain (original client)
        header
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp check_rate_limit(conn, key, opts) do
    bucket = "#{opts.namespace}:#{key}"

    case Hammer.check_rate(bucket, opts.window_ms, opts.limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        Logger.warning("[RateLimiter] Rate limit exceeded for #{bucket}")
        send_rate_limit_response(conn, opts.window_ms)
    end
  end

  defp send_rate_limit_response(conn, window_ms) do
    retry_after_seconds = ceil(window_ms / 1000)

    conn
    |> put_resp_header("retry-after", to_string(retry_after_seconds))
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(%{
      error: "rate_limit_exceeded",
      message: "Too many requests. Please try again later.",
      retry_after_seconds: retry_after_seconds
    }))
    |> halt()
  end
end
