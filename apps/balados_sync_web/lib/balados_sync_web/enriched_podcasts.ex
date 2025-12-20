defmodule BaladosSyncWeb.EnrichedPodcasts do
  @moduledoc """
  Context for managing enriched podcast entries.

  Enriched podcasts are admin-managed entries that provide:
  - Custom URL slugs (e.g., `/podcast/my-show`)
  - Branding (background color)
  - Social/custom links

  This is system data (not event-sourced), stored in the system schema.
  """

  import Ecto.Query
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.EnrichedPodcast

  @doc """
  Gets an enriched podcast by slug.
  """
  def get_by_slug(slug) when is_binary(slug) do
    SystemRepo.get_by(EnrichedPodcast, slug: slug)
  end

  @doc """
  Gets an enriched podcast by feed URL.
  """
  def get_by_feed_url(feed_url) when is_binary(feed_url) do
    SystemRepo.get_by(EnrichedPodcast, feed_url: feed_url)
  end

  @doc """
  Gets an enriched podcast by base64-encoded feed URL.
  Returns nil if decoding fails or not found.
  """
  def get_by_encoded_feed(encoded_feed) when is_binary(encoded_feed) do
    case Base.url_decode64(encoded_feed, padding: false) do
      {:ok, feed_url} -> get_by_feed_url(feed_url)
      :error -> nil
    end
  end

  @doc """
  Gets an enriched podcast by ID.
  """
  def get(id) when is_binary(id) do
    SystemRepo.get(EnrichedPodcast, id)
  end

  @doc """
  Lists all enriched podcasts, ordered by creation date (newest first).
  """
  def list_enriched_podcasts do
    EnrichedPodcast
    |> order_by(desc: :inserted_at)
    |> SystemRepo.all()
  end

  @doc """
  Creates an enriched podcast.
  """
  def create_enriched_podcast(attrs) do
    %EnrichedPodcast{}
    |> EnrichedPodcast.changeset(attrs)
    |> SystemRepo.insert()
  end

  @doc """
  Updates an enriched podcast.
  """
  def update_enriched_podcast(%EnrichedPodcast{} = enriched_podcast, attrs) do
    enriched_podcast
    |> EnrichedPodcast.changeset(attrs)
    |> SystemRepo.update()
  end

  @doc """
  Deletes an enriched podcast.
  """
  def delete_enriched_podcast(%EnrichedPodcast{} = enriched_podcast) do
    SystemRepo.delete(enriched_podcast)
  end

  @doc """
  Returns a changeset for tracking changes.
  """
  def change_enriched_podcast(%EnrichedPodcast{} = enriched_podcast, attrs \\ %{}) do
    EnrichedPodcast.changeset(enriched_podcast, attrs)
  end

  @doc """
  Checks if a slug is available.
  """
  def slug_available?(slug) when is_binary(slug) do
    is_nil(get_by_slug(slug))
  end

  @doc """
  Checks if a feed URL already has an enrichment.
  """
  def feed_url_available?(feed_url) when is_binary(feed_url) do
    is_nil(get_by_feed_url(feed_url))
  end

  @doc """
  Resolves a slug or encoded feed to an enrichment and feed URL.

  Returns `{:slug, feed_url, enrichment}` if resolved by slug,
  `{:encoded, feed_url, enrichment | nil}` if resolved by base64,
  or `{:error, :invalid}` if neither works.
  """
  def resolve_slug_or_encoded(slug_or_encoded) when is_binary(slug_or_encoded) do
    # Try slug first
    case get_by_slug(slug_or_encoded) do
      %EnrichedPodcast{} = enrichment ->
        {:slug, enrichment.feed_url, enrichment}

      nil ->
        # Try base64 decode
        case Base.url_decode64(slug_or_encoded, padding: false) do
          {:ok, feed_url} ->
            enrichment = get_by_feed_url(feed_url)
            {:encoded, feed_url, enrichment}

          :error ->
            {:error, :invalid}
        end
    end
  end
end
