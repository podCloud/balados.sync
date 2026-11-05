defmodule BaladosSyncWeb.RssProxyController do
  @moduledoc """
  CORS proxy for RSS feeds, used by balados.app when a feed does not allow
  cross-origin requests.

  The proxy requires a JWT with a scope that already grants access to the
  user's subscriptions (`user.sync` or `user.subscriptions.read`): without it
  the endpoint would be an open proxy. Requests are rate limited per user
  (quota shared across the user's devices) so a leaked token cannot turn the
  server into a free fetcher.

  Audio enclosures are never proxied; only the feed XML is.
  """
  use BaladosSyncWeb, :controller
  require Logger

  alias BaladosSyncCore.RssCache
  alias BaladosSyncWeb.Plugs.{JWTAuth, RateLimiter}
  import BaladosSyncWeb.ErrorHelpers

  plug JWTAuth, scopes_any: ["user.sync", "user.subscriptions.read"]

  # 120/min is well above `subs_metadata` (20/min) on purpose: the app only
  # reaches the proxy for feeds that block CORS and refreshes a whole library
  # at once; the quota is shared by all devices of the account.

  plug RateLimiter,
    limit: 120,
    window_ms: 60_000,
    key: :user_id,
    namespace: "rss_proxy"

  @doc "Cache policy for proxied feeds: the response is per-user (JWT), so never shared caches."
  def cache_control, do: "private, max-age=300"

  def proxy(conn, %{"encoded_feed_id" => encoded_feed_id}) do
    with {:ok, feed_url} <- decode_feed_id(encoded_feed_id),
         {:ok, feed_xml} <- RssCache.fetch_feed(feed_url) do
      conn
      |> put_resp_header("content-type", "application/xml; charset=utf-8")
      |> put_resp_header("cache-control", cache_control())
      |> send_resp(200, feed_xml)
    else
      {:error, :invalid_base64} ->
        bad_request(conn, "Invalid feed ID encoding")

      {:error, :url_blocked} ->
        bad_request(conn, "Feed URL not allowed")

      {:error, :fetch_failed} ->
        bad_gateway(conn, "Failed to fetch RSS feed")
    end
  end

  def proxy_episode(conn, %{
        "encoded_feed_id" => encoded_feed_id,
        "encoded_episode_id" => encoded_episode_id
      }) do
    with {:ok, feed_url} <- decode_feed_id(encoded_feed_id),
         {:ok, {guid, enclosure}} <- decode_episode_id(encoded_episode_id),
         {:ok, feed_xml} <- RssCache.fetch_feed(feed_url),
         {:ok, filtered_xml} <- filter_episode(feed_xml, guid, enclosure) do
      conn
      |> put_resp_header("content-type", "application/xml; charset=utf-8")
      |> put_resp_header("cache-control", cache_control())
      |> send_resp(200, filtered_xml)
    else
      {:error, :invalid_base64} ->
        bad_request(conn, "Invalid feed or episode ID encoding")

      {:error, :url_blocked} ->
        bad_request(conn, "Feed URL not allowed")

      {:error, :fetch_failed} ->
        bad_gateway(conn, "Failed to fetch RSS feed")

      {:error, :episode_not_found} ->
        not_found(conn, "Episode not found in feed")
    end
  end

  defp decode_feed_id(encoded) do
    # Try URL-safe base64 first, fallback to standard base64
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} ->
        {:ok, decoded}

      :error ->
        # Fallback to standard base64 for backwards compatibility
        case Base.decode64(encoded, padding: false) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_base64}
        end
    end
  end

  defp decode_episode_id(encoded) do
    # Try URL-safe base64 first, fallback to standard base64
    decoded =
      case Base.url_decode64(encoded, padding: false) do
        {:ok, decoded} ->
          {:ok, decoded}

        :error ->
          # Fallback to standard base64 for backwards compatibility
          Base.decode64(encoded, padding: false)
      end

    case decoded do
      {:ok, decoded} ->
        case String.split(decoded, ",", parts: 2) do
          [guid, enclosure] -> {:ok, {guid, enclosure}}
          [guid] -> {:ok, {guid, nil}}
        end

      :error ->
        {:error, :invalid_base64}
    end
  end

  defp filter_episode(xml, target_guid, target_enclosure) do
    case parse_and_filter_xml(xml, target_guid, target_enclosure) do
      {:ok, filtered} -> {:ok, filtered}
      :error -> {:error, :episode_not_found}
    end
  end

  defp parse_and_filter_xml(xml, target_guid, target_enclosure) do
    try do
      import SweetXml

      doc = xml |> parse()
      items = doc |> xpath(~x"//item"l)

      matching_item =
        Enum.find(items, fn item ->
          guid = item |> xpath(~x"./guid/text()"s)
          enclosure_url = item |> xpath(~x"./enclosure/@url"s)

          guid_match = guid == target_guid
          enclosure_match = is_nil(target_enclosure) or enclosure_url == target_enclosure

          guid_match and enclosure_match
        end)

      case matching_item do
        nil -> :error
        _item -> {:ok, xml}
      end
    rescue
      e ->
        Logger.error("XML parsing error: #{inspect(e)}")
        :error
    end
  end
end
