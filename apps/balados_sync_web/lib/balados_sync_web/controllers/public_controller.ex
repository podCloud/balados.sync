defmodule BaladosSyncWeb.PublicController do
  use BaladosSyncWeb, :controller

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
end
