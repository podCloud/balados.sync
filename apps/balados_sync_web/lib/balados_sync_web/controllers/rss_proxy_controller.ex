defmodule BaladosSyncWeb.RssProxyController do
  use BaladosSyncWeb, :controller
  require Logger

  alias BaladosSyncCore.RssCache

  def proxy(conn, %{"encoded_feed_id" => encoded_feed_id}) do
    with {:ok, feed_url} <- decode_feed_id(encoded_feed_id),
         {:ok, feed_xml} <- RssCache.fetch_feed(feed_url) do
      conn
      |> put_resp_header("content-type", "application/xml; charset=utf-8")
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "Content-Type")
      |> put_resp_header("cache-control", "public, max-age=300")
      |> send_resp(200, feed_xml)
    else
      {:error, :invalid_base64} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid feed ID encoding"})

      {:error, :fetch_failed} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Failed to fetch RSS feed"})

      {:error, reason} ->
        Logger.error("RSS proxy error: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
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
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "Content-Type")
      |> put_resp_header("cache-control", "public, max-age=300")
      |> send_resp(200, filtered_xml)
    else
      {:error, :episode_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Episode not found in feed"})

      {:error, reason} ->
        Logger.error("RSS proxy episode error: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  defp decode_feed_id(encoded) do
    # Try URL-safe base64 first, fallback to standard base64
    case Base.url_decode64(encoded) do
      {:ok, decoded} -> {:ok, decoded}
      :error ->
        # Fallback to standard base64 for backwards compatibility
        case Base.decode64(encoded) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_base64}
        end
    end
  end

  defp decode_episode_id(encoded) do
    # Try URL-safe base64 first, fallback to standard base64
    decoded =
      case Base.url_decode64(encoded) do
        {:ok, decoded} -> {:ok, decoded}
        :error ->
          # Fallback to standard base64 for backwards compatibility
          Base.decode64(encoded)
      end

    case decoded do
      {:ok, decoded} ->
        case String.split(decoded, ",", parts: 2) do
          [guid, enclosure] -> {:ok, {guid, enclosure}}
          [guid] -> {:ok, {guid, nil}}
          _ -> {:error, :invalid_format}
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
