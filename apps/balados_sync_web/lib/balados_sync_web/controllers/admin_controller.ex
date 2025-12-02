defmodule BaladosSyncWeb.AdminController do
  use BaladosSyncWeb, :controller
  alias BaladosSyncWeb.Accounts
  alias BaladosSyncWeb.RssCache
  alias BaladosSyncProjections.ProjectionsRepo
  import Ecto.Query

  plug :require_admin

  def index(conn, _params) do
    stats = get_system_stats()
    render(conn, :index, stats: stats)
  end

  def rss_utility(conn, _params) do
    render(conn, :rss_utility)
  end

  def generate_rss_link(conn, %{"feed_url" => feed_url}) do
    encoded_feed = Base.url_encode64(feed_url, padding: false)
    proxy_url = unverified_url(conn, ~p"/api/v1/rss/proxy/#{encoded_feed}")

    # Vérifier cache stats
    cache_stats = get_cache_stats(feed_url)

    json(conn, %{
      proxy_url: proxy_url,
      encoded_feed: encoded_feed,
      cache: cache_stats
    })
  end

  defp require_admin(conn, _opts) do
    if conn.assigns[:current_user] && Accounts.admin?(conn.assigns.current_user) do
      conn
    else
      conn
      |> put_flash(:error, "Admin access required")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp get_system_stats do
    %{
      total_users: count_users(),
      distinct_feeds: count_distinct_feeds(),
      event_rates: calculate_event_rates(),
      top_podcasts: get_top_podcasts(10),
      top_episodes: get_top_episodes(10)
    }
  end

  defp count_users do
    Accounts.count_users()
  end

  defp count_distinct_feeds do
    # Compte les feeds distincts dans l'EventStore
    query = """
    SELECT COUNT(DISTINCT data->>'rss_source_feed')
    FROM events.events
    WHERE data->>'rss_source_feed' IS NOT NULL
    """

    case ProjectionsRepo.query(query) do
      {:ok, %{rows: [[count]]}} -> count || 0
      _ -> 0
    end
  end

  defp calculate_event_rates do
    # Taux global
    query_total = """
    SELECT
      COUNT(*) as total_events,
      MIN(created_at) as first_event
    FROM events.events
    """

    # Taux récent (5 dernières minutes)
    query_recent = """
    SELECT COUNT(*) as recent_events
    FROM events.events
    WHERE created_at >= NOW() - INTERVAL '5 minutes'
    """

    with {:ok, %{rows: [[total, first_event]]}} <- ProjectionsRepo.query(query_total),
         {:ok, %{rows: [[recent]]}} <- ProjectionsRepo.query(query_recent) do
      # Calculer taux global
      global_rate =
        if first_event && total > 0 do
          duration_seconds = DateTime.diff(DateTime.utc_now(), first_event, :second)
          if duration_seconds > 0, do: total * 1.0 / duration_seconds, else: 0.0
        else
          0.0
        end

      # Calculer taux récent (events/seconde sur 5 min)
      recent_rate = recent / 300.0

      %{
        global: %{
          events_per_second: Float.round(global_rate, 2),
          events_per_minute: Float.round(global_rate * 60, 2),
          events_per_hour: Float.round(global_rate * 3600, 2),
          total_events: total
        },
        recent: %{
          events_per_second: Float.round(recent_rate, 2),
          events_per_minute: Float.round(recent_rate * 60, 2),
          events_per_hour: Float.round(recent_rate * 3600, 2),
          recent_events: recent,
          period: "5 minutes"
        }
      }
    else
      _ -> %{global: %{}, recent: %{}}
    end
  end

  defp get_top_podcasts(limit) do
    query =
      from(p in "podcast_popularity",
        select: %{
          feed: p.rss_source_feed,
          score: p.score,
          plays: p.plays,
          likes: p.likes
        },
        order_by: [desc: p.score],
        limit: ^limit
      )

    ProjectionsRepo.all(query)
    |> Enum.map(&enrich_podcast_title/1)
  end

  defp enrich_podcast_title(podcast) do
    with {:ok, feed_url} <- Base.url_decode64(podcast.feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      podcast
      |> Map.put(:title, metadata.title)
      |> Map.put(:website_link, metadata.link)
      |> Map.put(:feed_url, feed_url)
    else
      _ ->
        podcast
        |> Map.put(:title, nil)
        |> Map.put(:website_link, nil)
        |> Map.put(:feed_url, nil)
    end
  end

  defp get_top_episodes(limit) do
    query =
      from(e in "episode_popularity",
        select: %{
          feed: e.rss_source_feed,
          item: e.rss_source_item,
          score: e.score,
          plays: e.plays,
          likes: e.likes
        },
        order_by: [desc: e.score],
        limit: ^limit
      )

    ProjectionsRepo.all(query)
    |> Enum.map(&enrich_episode_title/1)
  end

  defp enrich_episode_title(episode) do
    with {:ok, feed_url} <- Base.url_decode64(episode.feed, padding: false),
         {:ok, guid} <- extract_guid_from_item(episode.item),
         {:ok, xml} <- RssCache.fetch_feed(feed_url),
         {:ok, episodes} <- BaladosSyncWeb.RssParser.parse_episodes(xml) do
      # Find episode by guid
      found_episode = Enum.find(episodes, fn ep -> ep.guid == guid end)

      episode
      |> Map.put(:title, found_episode && found_episode.title)
      |> Map.put(:guid, guid)
      |> Map.put(:episode_link, found_episode && (found_episode.link || found_episode.enclosure && found_episode.enclosure.url))
      |> Map.put(:feed_url, feed_url)
    else
      _ ->
        episode
        |> Map.put(:title, nil)
        |> Map.put(:guid, nil)
        |> Map.put(:episode_link, nil)
        |> Map.put(:feed_url, nil)
    end
  end

  defp extract_guid_from_item(encoded_item) do
    with {:ok, decoded} <- Base.url_decode64(encoded_item, padding: false) do
      parts = String.split(decoded, ",", parts: 2)
      guid = Enum.at(parts, 1)

      if guid do
        {:ok, guid}
      else
        {:error, :invalid_format}
      end
    else
      :error -> {:error, :invalid_encoding}
    end
  end

  defp get_cache_stats(feed_url) do
    case BaladosSyncWeb.RssCache.get(feed_url) do
      {:ok, _content} ->
        %{
          cached: true,
          ttl: "5 minutes"
        }

      :miss ->
        %{
          cached: false,
          ttl: nil
        }
    end
  end
end
