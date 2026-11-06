defmodule BaladosSyncCore.SafeHttp do
  @moduledoc """
  Outbound HTTP GET for third-party URLs (RSS feeds), protected against SSRF.

  The initial URL **and every redirect target** go through
  `BaladosSyncCore.UrlValidator.validate_rss_url/1` before any request is
  made: Req's automatic redirects are disabled and redirects are followed
  here, at most #{5} hops, so a public feed answering
  `302 Location: http://169.254.169.254/…` is refused instead of fetched.

  Returns:

    * `{:ok, body}` for a 200 response
    * `{:error, :url_blocked}` when the URL or a redirect target is refused
    * `{:error, {:http_error, status}}` for any other status (or a redirect
      without `Location`)
    * `{:error, {:network_error, reason}}` for transport errors
    * `{:error, :too_many_redirects}` after #{5} redirects

  Options: `:headers` (list of `{name, value}`), `:timeout` in ms (connect
  and receive, default 10 000). `:req_options` is merged into the Req request
  and exists for tests (`plug: {Req.Test, name}`).
  """

  require Logger

  alias BaladosSyncCore.UrlValidator

  @max_redirects 5
  @redirect_statuses [301, 302, 303, 307, 308]
  @default_timeout 10_000

  @type error ::
          :url_blocked
          | :too_many_redirects
          | {:http_error, pos_integer()}
          | {:network_error, term()}

  @spec get(String.t(), keyword()) :: {:ok, binary()} | {:error, error()}
  def get(url, opts \\ []) when is_binary(url), do: do_get(url, opts, 0)

  defp do_get(url, opts, hops) do
    case UrlValidator.validate_rss_url(url) do
      :ok ->
        url |> request(opts) |> handle_response(url, opts, hops)

      {:error, reason} ->
        Logger.warning("[SafeHttp] URL blocked (#{reason}): #{loggable(url)}")
        {:error, :url_blocked}
    end
  end

  defp request(url, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    [
      url: url,
      headers: Keyword.get(opts, :headers, []),
      user_agent: user_agent(),
      redirect: false,
      retry: false,
      decode_body: false,
      receive_timeout: timeout,
      connect_options: [timeout: timeout]
    ]
    |> Keyword.merge(Keyword.get(opts, :req_options, []))
    |> Req.get()
  rescue
    # Finch raises (instead of returning) when no pooled connection frees up
    # within its pool timeout; hackney used to return {:error, :checkout_timeout}.
    # Keep the tuple contract so callers degrade to :fetch_failed, not a 500.
    e in RuntimeError ->
      if String.starts_with?(e.message, "Finch was unable to provide a connection"),
        do: {:error, e},
        else: reraise(e, __STACKTRACE__)
  end

  defp user_agent do
    "Balados/#{Application.spec(:balados_sync_core, :vsn) || "dev"} (+https://github.com/podCloud/balados.sync)"
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}, _url, _opts, _hops),
    do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status} = resp}, url, opts, hops)
       when status in @redirect_statuses do
    case Req.Response.get_header(resp, "location") do
      [] ->
        {:error, {:http_error, status}}

      [_location | _] when hops >= @max_redirects ->
        Logger.warning("[SafeHttp] too many redirects from #{loggable(url)}")
        {:error, :too_many_redirects}

      [location | _] ->
        url |> URI.merge(location) |> URI.to_string() |> do_get(opts, hops + 1)
    end
  end

  defp handle_response({:ok, %Req.Response{status: status}}, _url, _opts, _hops),
    do: {:error, {:http_error, status}}

  defp handle_response({:error, %{reason: reason}}, _url, _opts, _hops),
    do: {:error, {:network_error, reason}}

  defp handle_response({:error, exception}, _url, _opts, _hops),
    do: {:error, {:network_error, exception}}

  @doc """
  URL safe to log: the `user:pass@` part, the query string and the fragment
  are removed (private feeds carry their access token in either).
  """
  @spec loggable(String.t()) :: String.t()
  def loggable(url) do
    url
    |> URI.parse()
    |> Map.merge(%{userinfo: nil, query: nil, fragment: nil})
    |> URI.to_string()
  end
end
