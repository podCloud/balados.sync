defmodule BaladosSyncWeb.RssAggregateController do
  use BaladosSyncWeb, :controller
  require Logger

  alias BaladosSyncCore.RssCache
  alias BaladosSyncWeb.PlayTokenHelper
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{PlayToken, Subscription, Playlist, PlaylistItem, Collection, CollectionSubscription}
  import Ecto.Query

  def subscriptions(conn, %{"user_token" => token}) do
    with {:ok, user_id} <- verify_user_token(token),
         {:ok, subscriptions} <- get_user_subscriptions(user_id),
         {:ok, aggregated_feed} <- aggregate_subscription_feeds(user_id, token, subscriptions) do
      update_token_last_used(token)

      conn
      |> put_resp_header("content-type", "application/xml; charset=utf-8")
      |> put_resp_header("cache-control", "private, max-age=60")
      |> send_resp(200, aggregated_feed)
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or revoked token"})

      {:error, reason} ->
        Logger.error("RSS aggregate error: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  def collection(conn, %{"user_token" => token, "collection_id" => collection_id}) do
    with {:ok, user_id} <- verify_user_token(token),
         {:ok, collection} <- get_user_collection(user_id, collection_id),
         {:ok, subscriptions} <- get_collection_subscriptions(collection.id),
         {:ok, aggregated_feed} <- aggregate_collection_feeds(user_id, token, collection, subscriptions) do
      update_token_last_used(token)

      conn
      |> put_resp_header("content-type", "application/xml; charset=utf-8")
      |> put_resp_header("cache-control", "private, max-age=60")
      |> send_resp(200, aggregated_feed)
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or revoked token"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Collection not found"})

      {:error, reason} ->
        Logger.error("RSS collection error: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  def playlist(conn, %{"user_token" => token, "playlist_id" => playlist_id}) do
    with {:ok, user_id} <- verify_user_token(token),
         {:ok, playlist} <- get_user_playlist(user_id, playlist_id),
         {:ok, aggregated_feed} <- aggregate_playlist_feed(user_id, token, playlist) do
      update_token_last_used(token)

      conn
      |> put_resp_header("content-type", "application/xml; charset=utf-8")
      |> put_resp_header("cache-control", "private, max-age=60")
      |> send_resp(200, aggregated_feed)
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or revoked token"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Playlist not found"})

      {:error, reason} ->
        Logger.error("RSS playlist error: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  defp verify_user_token(token) do
    query =
      from(t in PlayToken,
        where: t.token == ^token and is_nil(t.revoked_at),
        select: t.user_id
      )

    case SystemRepo.one(query) do
      nil -> {:error, :invalid_token}
      user_id -> {:ok, user_id}
    end
  end

  defp get_user_subscriptions(user_id) do
    subscriptions =
      from(s in Subscription,
        where: s.user_id == ^user_id,
        where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at,
        select: %{feed: s.rss_source_feed, title: s.rss_feed_title}
      )
      |> ProjectionsRepo.all()

    {:ok, subscriptions}
  end

  defp get_user_collection(user_id, collection_id) do
    collection =
      from(c in Collection,
        where: c.user_id == ^user_id and c.id == ^collection_id and is_nil(c.deleted_at)
      )
      |> ProjectionsRepo.one()

    case collection do
      nil -> {:error, :not_found}
      collection -> {:ok, collection}
    end
  end

  defp get_collection_subscriptions(collection_id) do
    subscriptions =
      from(cs in CollectionSubscription,
        join: s in Subscription,
        on: cs.rss_source_feed == s.rss_source_feed,
        where: cs.collection_id == ^collection_id,
        where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at,
        select: %{feed: s.rss_source_feed, title: s.rss_feed_title}
      )
      |> ProjectionsRepo.all()

    {:ok, subscriptions}
  end

  defp get_user_playlist(user_id, playlist_id) do
    playlist =
      from(p in Playlist,
        where: p.user_id == ^user_id and p.id == ^playlist_id,
        preload: [items: ^from(pi in PlaylistItem, where: is_nil(pi.deleted_at))]
      )
      |> ProjectionsRepo.one()

    case playlist do
      nil -> {:error, :not_found}
      playlist -> {:ok, playlist}
    end
  end

  defp aggregate_subscription_feeds(_user_id, user_token, subscriptions) do
    tasks =
      Enum.map(subscriptions, fn sub ->
        Task.async(fn ->
          case decode_feed_url(sub.feed) do
            {:ok, feed_url} ->
              case RssCache.fetch_feed(feed_url) do
                {:ok, xml} ->
                  parse_and_transform_items(xml, sub.feed, sub.title || "Unknown Podcast", user_token)

                error ->
                  Logger.error("Failed to fetch feed #{sub.title}: #{inspect(error)}")
                  {:error, :fetch_failed}
              end

            {:error, :invalid_encoding} ->
              Logger.error("Invalid base64 feed encoding for #{sub.title}: #{sub.feed}")
              {:error, :invalid_encoding}
          end
        end)
      end)

    results = Task.await_many(tasks, :timer.seconds(30))

    # Collecter tous les items transformés
    all_items =
      results
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.flat_map(fn {:ok, items} -> items end)
      |> Enum.sort_by(& &1.pub_date_parsed, {:desc, DateTime})
      |> Enum.take(100)

    feed_xml =
      build_aggregated_feed(
        "My Subscriptions",
        "Aggregated feed from all your subscriptions",
        all_items
      )

    {:ok, feed_xml}
  end

  defp aggregate_collection_feeds(_user_id, user_token, collection, subscriptions) do
    tasks =
      Enum.map(subscriptions, fn sub ->
        Task.async(fn ->
          case decode_feed_url(sub.feed) do
            {:ok, feed_url} ->
              case RssCache.fetch_feed(feed_url) do
                {:ok, xml} ->
                  parse_and_transform_items(xml, sub.feed, sub.title || "Unknown Podcast", user_token)

                error ->
                  Logger.error("Failed to fetch feed #{sub.title}: #{inspect(error)}")
                  {:error, :fetch_failed}
              end

            {:error, :invalid_encoding} ->
              Logger.error("Invalid base64 feed encoding for #{sub.title}: #{sub.feed}")
              {:error, :invalid_encoding}
          end
        end)
      end)

    results = Task.await_many(tasks, :timer.seconds(30))

    # Collecter tous les items transformés
    all_items =
      results
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.flat_map(fn {:ok, items} -> items end)
      |> Enum.sort_by(& &1.pub_date_parsed, {:desc, DateTime})
      |> Enum.take(100)

    feed_xml =
      build_aggregated_feed(
        collection.title,
        collection.description || "Aggregated feed from collection: #{collection.title}",
        all_items
      )

    {:ok, feed_xml}
  end

  defp aggregate_playlist_feed(_user_id, user_token, playlist) do
    items_by_feed = Enum.group_by(playlist.items, & &1.rss_source_feed)

    tasks =
      Enum.map(items_by_feed, fn {feed, items} ->
        Task.async(fn ->
          feed_title = List.first(items).feed_title || "Unknown Podcast"
          item_ids = Enum.map(items, & &1.rss_source_item)

          case decode_feed_url(feed) do
            {:ok, feed_url} ->
              case RssCache.fetch_feed(feed_url) do
                {:ok, xml} ->
                  parse_and_transform_items(xml, feed, feed_title, user_token, item_ids)

                error ->
                  Logger.error("Failed to fetch playlist feed: #{inspect(error)}")
                  {:error, :fetch_failed}
              end

            {:error, :invalid_encoding} ->
              Logger.error("Invalid base64 feed encoding for playlist: #{feed}")
              {:error, :invalid_encoding}
          end
        end)
      end)

    results = Task.await_many(tasks, :timer.seconds(30))

    all_items =
      results
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.flat_map(fn {:ok, items} -> items end)

    feed_xml =
      build_aggregated_feed(
        playlist.name,
        playlist.description || "Playlist feed",
        all_items
      )

    {:ok, feed_xml}
  end

  defp parse_and_transform_items(
         xml,
         encoded_feed,
         feed_title,
         user_token,
         filter_item_ids \\ nil
       ) do
    import SweetXml

    try do
      doc = xml |> parse()
      items = doc |> xpath(~x"//item"l)

      transformed_items =
        items
        |> Enum.map(fn item_node ->
          # Extraire les infos nécessaires
          guid = item_node |> xpath(~x"./guid/text()"s)
          original_title = item_node |> xpath(~x"./title/text()"s)
          enclosure_url = item_node |> xpath(~x"./enclosure/@url"s)
          pub_date_str = item_node |> xpath(~x"./pubDate/text()"s)

          # Parser la date
          pub_date_parsed = parse_pub_date(pub_date_str)

          # Construire l'item_id et l'URL play (URL-safe encoding)
          item_id_encoded = Base.url_encode64("#{guid},#{enclosure_url}", padding: false)
          play_url = PlayTokenHelper.build_play_url(user_token, encoded_feed, item_id_encoded)

          # Nouveau titre avec format "Podcast Name - Episode Title"
          new_title = "#{feed_title} - #{original_title}"

          # Convertir l'item en XML string et transformer
          item_xml =
            item_node
            |> :xmerl.export_simple_element(:xmerl_xml)
            |> IO.iodata_to_binary()

          # Remplacer le titre et l'URL d'enclosure dans le XML
          transformed_xml =
            item_xml
            |> String.replace(~r/<title>.*?<\/title>/, "<title>#{escape_xml(new_title)}</title>")
            |> String.replace(
              ~r/<enclosure([^>]*url=")[^"]*"/,
              "<enclosure\\1#{escape_xml(play_url)}\""
            )

          %{
            xml: transformed_xml,
            guid: guid,
            pub_date_parsed: pub_date_parsed
          }
        end)

      # Filtrer si nécessaire
      final_items =
        if filter_item_ids do
          # Décoder les guids des filter_item_ids (URL-safe encoding)
          target_guids =
            Enum.map(filter_item_ids, fn encoded ->
              case Base.url_decode64(encoded, padding: false) do
                {:ok, decoded} ->
                  [guid | _] = String.split(decoded, ",", parts: 2)
                  guid

                _ ->
                  nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          Enum.filter(transformed_items, fn item ->
            item.guid in target_guids
          end)
        else
          transformed_items
        end

      {:ok, final_items}
    rescue
      e ->
        Logger.error("XML parsing/transformation error: #{inspect(e)}")
        {:error, :parse_error}
    end
  end

  defp parse_pub_date(date_str) do
    case Timex.parse(date_str, "{RFC1123}") do
      {:ok, datetime} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp build_aggregated_feed(title, description, items) do
    items_xml = Enum.map(items, & &1.xml) |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>#{escape_xml(title)}</title>
        <description>#{escape_xml(description)}</description>
        <language>en</language>
        <pubDate>#{format_rfc1123(DateTime.utc_now())}</pubDate>
        #{items_xml}
      </channel>
    </rss>
    """
  end

  defp escape_xml(nil), do: ""

  defp escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(other), do: to_string(other) |> escape_xml()

  defp format_rfc1123(datetime) do
    Timex.format!(datetime, "{RFC1123}")
  end

  defp decode_feed_url(encoded_feed) do
    case Base.url_decode64(encoded_feed, padding: false) do
      {:ok, feed_url} -> {:ok, feed_url}
      :error -> {:error, :invalid_encoding}
    end
  end

  defp update_token_last_used(token) do
    Task.start(fn ->
      from(t in PlayToken, where: t.token == ^token)
      |> SystemRepo.update_all(set: [last_used_at: DateTime.utc_now()])
    end)
  end
end
