defmodule BaladosSyncWeb.EnrichedPodcastsController do
  @moduledoc """
  Admin controller for managing enriched podcast entries.

  Provides CRUD operations for creating and managing podcast enrichments
  with custom slugs, branding, and social links.
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.Accounts
  alias BaladosSyncWeb.EnrichedPodcasts
  alias BaladosSyncProjections.Schemas.EnrichedPodcast
  alias BaladosSyncCore.RssCache

  plug :require_admin

  def index(conn, _params) do
    enriched_podcasts = EnrichedPodcasts.list_enriched_podcasts()
    render(conn, :index, enriched_podcasts: enriched_podcasts)
  end

  def new(conn, params) do
    changeset = EnrichedPodcasts.change_enriched_podcast(%EnrichedPodcast{})
    feed_url = params["feed_url"]

    # If feed_url provided, fetch metadata for preview
    feed_metadata =
      if feed_url do
        case RssCache.get_feed_metadata(feed_url) do
          {:ok, metadata} -> metadata
          _ -> nil
        end
      end

    render(conn, :new,
      changeset: changeset,
      feed_url: feed_url,
      feed_metadata: feed_metadata,
      social_types: EnrichedPodcast.social_types()
    )
  end

  def create(conn, %{"enriched_podcast" => enriched_podcast_params}) do
    attrs =
      enriched_podcast_params
      |> Map.put("created_by_user_id", conn.assigns.current_user.id)
      |> parse_links_params()

    case EnrichedPodcasts.create_enriched_podcast(attrs) do
      {:ok, enriched_podcast} ->
        conn
        |> put_flash(:info, "Enriched podcast created successfully.")
        |> redirect(to: ~p"/admin/enriched-podcasts/#{enriched_podcast.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        feed_url = enriched_podcast_params["feed_url"]

        feed_metadata =
          if feed_url do
            case RssCache.get_feed_metadata(feed_url) do
              {:ok, metadata} -> metadata
              _ -> nil
            end
          end

        render(conn, :new,
          changeset: changeset,
          feed_url: feed_url,
          feed_metadata: feed_metadata,
          social_types: EnrichedPodcast.social_types()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    case EnrichedPodcasts.get(id) do
      nil ->
        conn
        |> put_flash(:error, "Enriched podcast not found.")
        |> redirect(to: ~p"/admin/enriched-podcasts")

      enriched_podcast ->
        # Fetch podcast metadata for display
        feed_metadata =
          case RssCache.get_feed_metadata(enriched_podcast.feed_url) do
            {:ok, metadata} -> metadata
            _ -> nil
          end

        stats = get_podcast_stats(enriched_podcast.feed_url)

        render(conn, :show,
          enriched_podcast: enriched_podcast,
          feed_metadata: feed_metadata,
          stats: stats
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    case EnrichedPodcasts.get(id) do
      nil ->
        conn
        |> put_flash(:error, "Enriched podcast not found.")
        |> redirect(to: ~p"/admin/enriched-podcasts")

      enriched_podcast ->
        changeset = EnrichedPodcasts.change_enriched_podcast(enriched_podcast)

        feed_metadata =
          case RssCache.get_feed_metadata(enriched_podcast.feed_url) do
            {:ok, metadata} -> metadata
            _ -> nil
          end

        render(conn, :edit,
          enriched_podcast: enriched_podcast,
          changeset: changeset,
          feed_metadata: feed_metadata,
          social_types: EnrichedPodcast.social_types()
        )
    end
  end

  def update(conn, %{"id" => id, "enriched_podcast" => enriched_podcast_params}) do
    case EnrichedPodcasts.get(id) do
      nil ->
        conn
        |> put_flash(:error, "Enriched podcast not found.")
        |> redirect(to: ~p"/admin/enriched-podcasts")

      enriched_podcast ->
        attrs = parse_links_params(enriched_podcast_params)

        case EnrichedPodcasts.update_enriched_podcast(enriched_podcast, attrs) do
          {:ok, enriched_podcast} ->
            conn
            |> put_flash(:info, "Enriched podcast updated successfully.")
            |> redirect(to: ~p"/admin/enriched-podcasts/#{enriched_podcast.id}")

          {:error, %Ecto.Changeset{} = changeset} ->
            feed_metadata =
              case RssCache.get_feed_metadata(enriched_podcast.feed_url) do
                {:ok, metadata} -> metadata
                _ -> nil
              end

            render(conn, :edit,
              enriched_podcast: enriched_podcast,
              changeset: changeset,
              feed_metadata: feed_metadata,
              social_types: EnrichedPodcast.social_types()
            )
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case EnrichedPodcasts.get(id) do
      nil ->
        conn
        |> put_flash(:error, "Enriched podcast not found.")
        |> redirect(to: ~p"/admin/enriched-podcasts")

      enriched_podcast ->
        {:ok, _} = EnrichedPodcasts.delete_enriched_podcast(enriched_podcast)

        conn
        |> put_flash(:info, "Enriched podcast deleted successfully.")
        |> redirect(to: ~p"/admin/enriched-podcasts")
    end
  end

  def check_slug(conn, %{"slug" => slug}) do
    available = EnrichedPodcasts.slug_available?(slug)
    json(conn, %{available: available})
  end

  # Private functions

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

  defp parse_links_params(params) do
    case params["links"] do
      nil ->
        params

      "" ->
        Map.put(params, "links", [])

      links when is_list(links) ->
        # Filter out empty links and convert to proper format
        parsed_links =
          links
          |> Enum.filter(fn link ->
            link["url"] && String.trim(link["url"]) != ""
          end)
          |> Enum.map(fn link ->
            if link["type"] == "custom" do
              %{"type" => "custom", "title" => link["title"] || "", "url" => link["url"]}
            else
              %{"type" => link["type"], "url" => link["url"]}
            end
          end)

        Map.put(params, "links", parsed_links)

      links when is_binary(links) ->
        # Try to parse as JSON
        case Jason.decode(links) do
          {:ok, parsed} -> Map.put(params, "links", parsed)
          _ -> Map.put(params, "links", [])
        end

      _ ->
        params
    end
  end

  defp get_podcast_stats(feed_url) do
    encoded_feed = Base.url_encode64(feed_url, padding: false)

    # Get popularity data
    alias BaladosSyncProjections.ProjectionsRepo
    import Ecto.Query

    popularity_query =
      from(p in "podcast_popularity",
        where: p.rss_source_feed == ^encoded_feed,
        select: %{
          score: p.score,
          plays: p.plays,
          likes: p.likes
        }
      )

    popularity = ProjectionsRepo.one(popularity_query)

    # Get subscriber count
    subscriber_query =
      from(s in "subscriptions",
        where: s.feed == ^encoded_feed,
        select: count(s.user_id)
      )

    subscriber_count = ProjectionsRepo.one(subscriber_query) || 0

    %{
      popularity: popularity || %{score: 0, plays: 0, likes: 0},
      subscriber_count: subscriber_count
    }
  end
end
