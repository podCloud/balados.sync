defmodule BaladosSyncWeb.PublicController do
  use BaladosSyncWeb, :controller

  require Logger

  alias BaladosSyncCore.RssCache
  alias BaladosSyncCore.RssParser
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, Unsubscribe}
  alias BaladosSyncProjections.ProjectionsRepo

  alias BaladosSyncProjections.Schemas.{
    PodcastPopularity,
    EpisodePopularity,
    PublicEvent
  }

  import Ecto.Query

  def trending_podcasts(conn, params) do
    limit = min(String.to_integer(params["limit"] || "20"), 100)

    # Podcasts avec le meilleur delta score
    query =
      from(p in PodcastPopularity,
        order_by: [desc: fragment("score - score_previous"), desc: :score],
        limit: ^limit
      )

    podcasts = ProjectionsRepo.all(query)

    json(conn, %{podcasts: podcasts})
  end

  def trending_episodes(conn, params) do
    limit = min(String.to_integer(params["limit"] || "20"), 100)
    feed = params["feed"]

    query =
      from(e in EpisodePopularity,
        order_by: [desc: fragment("score - score_previous"), desc: :score],
        limit: ^limit
      )

    query =
      if feed do
        from(e in query, where: e.rss_source_feed == ^feed)
      else
        query
      end

    episodes = ProjectionsRepo.all(query)

    json(conn, %{episodes: episodes})
  end

  def feed_popularity(conn, %{"feed" => feed}) do
    case ProjectionsRepo.get(PodcastPopularity, feed) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Podcast not found"})

      podcast ->
        json(conn, %{podcast: podcast})
    end
  end

  def episode_popularity(conn, %{"item" => item}) do
    case ProjectionsRepo.get(EpisodePopularity, item) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Episode not found"})

      episode ->
        json(conn, %{episode: episode})
    end
  end

  def timeline(conn, params) do
    limit = min(String.to_integer(params["limit"] || "50"), 100)
    offset = String.to_integer(params["offset"] || "0")

    # Filtres optionnels
    query =
      from(pe in PublicEvent,
        order_by: [desc: :event_timestamp],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if params["event_type"] do
        from(pe in query, where: pe.event_type == ^params["event_type"])
      else
        query
      end

    query =
      if params["feed"] do
        from(pe in query, where: pe.rss_source_feed == ^params["feed"])
      else
        query
      end

    query =
      if params["user_id"] do
        # Uniquement les events publics (pas anonymous)
        from(pe in query,
          where: pe.user_id == ^params["user_id"] and pe.privacy == "public"
        )
      else
        query
      end

    events = ProjectionsRepo.all(query)

    # Masquer les user_id si privacy == anonymous
    events =
      Enum.map(events, fn event ->
        if event.privacy == "anonymous" do
          %{event | user_id: nil}
        else
          event
        end
      end)

    json(conn, %{
      events: events,
      pagination: %{
        limit: limit,
        offset: offset
      }
    })
  end

  # ===== HTML Views for Public Discovery =====

  @doc """
  Display top 10 trending podcasts in HTML.
  """
  def trending_podcasts_html(conn, _params) do
    podcasts =
      from(p in PodcastPopularity,
        order_by: [desc: fragment("score - score_previous"), desc: :score],
        limit: 10
      )
      |> ProjectionsRepo.all()
      |> Enum.map(fn p -> Map.put(p, :metadata, fetch_metadata_safe(p.rss_source_feed)) end)

    render(conn, :trending_podcasts, podcasts: podcasts)
  end

  @doc """
  Display top 10 trending episodes in HTML.
  """
  def trending_episodes_html(conn, _params) do
    episodes =
      from(e in EpisodePopularity,
        order_by: [desc: fragment("score - score_previous"), desc: :score],
        limit: 10
      )
      |> ProjectionsRepo.all()

    render(conn, :trending_episodes, episodes: episodes)
  end

  @doc """
  Display a single podcast feed page with recent episodes.
  Shows conditional subscribe/unsubscribe buttons based on authentication status.
  """
  def feed_page(conn, %{"feed" => encoded_feed}) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, xml} <- RssCache.fetch_feed(feed_url),
         {:ok, metadata} <- RssParser.parse_feed(xml),
         {:ok, episodes} <- RssParser.parse_episodes(xml) do
      popularity = ProjectionsRepo.get(PodcastPopularity, encoded_feed)

      # Check if user is authenticated and subscribed
      current_user = conn.assigns[:current_user]

      is_subscribed =
        if current_user do
          BaladosSyncWeb.Queries.is_user_subscribed?(current_user.id, encoded_feed)
        else
          false
        end

      # Get subscription details if subscribed (for source_id in unsubscribe)
      subscription =
        if is_subscribed do
          BaladosSyncWeb.Queries.get_user_subscription(current_user.id, encoded_feed)
        else
          nil
        end

      render(conn, :feed_page,
        encoded_feed: encoded_feed,
        feed_url: feed_url,
        metadata: metadata,
        episodes: Enum.take(episodes, 20),
        popularity: popularity,
        is_subscribed: is_subscribed,
        subscription: subscription,
        current_user: current_user
      )
    else
      _ ->
        conn
        |> put_flash(:error, "Feed not found")
        |> redirect(to: ~p"/trending/podcasts")
    end
  end

  @doc """
  Display a single episode page with details and popularity stats.
  """
  def episode_page(conn, %{"item" => encoded_item}) do
    with {:ok, feed_url} <- decode_episode_feed(encoded_item),
         {:ok, xml} <- RssCache.fetch_feed(feed_url),
         {:ok, episodes} <- RssParser.parse_episodes(xml),
         episode when not is_nil(episode) <- find_episode(episodes, encoded_item) do
      popularity = ProjectionsRepo.get(EpisodePopularity, encoded_item)

      render(conn, :episode_page,
        episode: episode,
        feed_url: feed_url,
        encoded_item: encoded_item,
        popularity: popularity
      )
    else
      _ ->
        conn
        |> put_flash(:error, "Episode not found")
        |> redirect(to: ~p"/trending/episodes")
    end
  end

  @doc """
  Quick subscribe from public feed page.
  Requires authentication.
  """
  def subscribe_to_feed(conn, %{"feed" => encoded_feed}) do
    unless conn.assigns[:current_user] do
      conn
      |> put_flash(:error, "You must be logged in to subscribe")
      |> redirect(to: ~p"/users/log_in?return_to=/podcasts/#{encoded_feed}")
      |> halt()
    end

    user_id = conn.assigns.current_user.id

    case Base.url_decode64(encoded_feed, padding: false) do
      {:ok, feed_url} ->
        source_id = generate_source_id(feed_url)

        command = %Subscribe{
          user_id: user_id,
          rss_source_feed: encoded_feed,
          rss_source_id: source_id,
          subscribed_at: DateTime.utc_now(),
          event_infos: %{
            device_id: "web-#{:erlang.phash2(conn.remote_ip)}",
            device_name: "Web Browser"
          }
        }

        case Dispatcher.dispatch(command) do
          :ok ->
            conn
            |> put_flash(:info, "Successfully subscribed")
            |> redirect(to: ~p"/podcasts/#{encoded_feed}")

          {:error, :already_subscribed} ->
            conn
            |> put_flash(:warning, "Already subscribed")
            |> redirect(to: ~p"/podcasts/#{encoded_feed}")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to subscribe: #{inspect(reason)}")
            |> redirect(to: ~p"/podcasts/#{encoded_feed}")
        end

      :error ->
        conn
        |> put_flash(:error, "Invalid feed")
        |> redirect(to: ~p"/trending/podcasts")
    end
  end

  @doc """
  Quick unsubscribe from public feed page.
  Requires authentication and existing subscription.
  """
  def unsubscribe_from_feed(conn, %{"feed" => encoded_feed}) do
    unless conn.assigns[:current_user] do
      conn
      |> put_flash(:error, "You must be logged in")
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end

    user_id = conn.assigns.current_user.id

    subscription = BaladosSyncWeb.Queries.get_user_subscription(user_id, encoded_feed)

    unless subscription do
      conn
      |> put_flash(:error, "Not subscribed to this podcast")
      |> redirect(to: ~p"/podcasts/#{encoded_feed}")
      |> halt()
    end

    command = %Unsubscribe{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_id: subscription.rss_source_id,
      unsubscribed_at: DateTime.utc_now(),
      event_infos: %{
        device_id: "web-#{:erlang.phash2(conn.remote_ip)}",
        device_name: "Web Browser"
      }
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        conn
        |> put_flash(:info, "Successfully unsubscribed")
        |> redirect(to: ~p"/podcasts/#{encoded_feed}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to unsubscribe: #{inspect(reason)}")
        |> redirect(to: ~p"/podcasts/#{encoded_feed}")
    end
  end

  # ===== Private Helpers =====

  defp fetch_metadata_safe(encoded_feed) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      metadata
    else
      _ -> nil
    end
  end

  defp decode_episode_feed(encoded_item) do
    # Episode IDs are base64("feed_url,guid,enclosure")
    case Base.url_decode64(encoded_item, padding: false) do
      {:ok, decoded} ->
        case String.split(decoded, ",", parts: 2) do
          [feed_url, _rest] -> {:ok, feed_url}
          _ -> {:error, :invalid_format}
        end

      :error ->
        {:error, :invalid_encoding}
    end
  end

  defp find_episode(episodes, encoded_item) do
    with {:ok, decoded} <- Base.url_decode64(encoded_item, padding: false) do
      parts = String.split(decoded, ",")
      guid = Enum.at(parts, 1)

      if guid do
        Enum.find(episodes, fn ep -> ep.guid == guid end)
      else
        nil
      end
    else
      _ -> nil
    end
  end

  defp generate_source_id(feed_url) do
    :crypto.hash(:sha256, feed_url)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end
end
