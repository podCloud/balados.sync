defmodule BaladosSyncCore.RssCache do
  @moduledoc """
  Module de cache LRU pour les flux RSS avec TTL de 5 minutes
  """
  require Logger
  alias BaladosSyncCore.RssParser
  alias BaladosSyncCore.UrlValidator

  @cache_name :rss_feed_cache
  @cache_ttl :timer.minutes(5)

  @doc """
  Récupère un flux RSS, depuis le cache ou en le fetchant
  """
  def fetch_feed(feed_url) do
    cache_key = {:feed, feed_url}

    case get(cache_key) do
      {:ok, cached_xml} ->
        Logger.debug("RSS cache HIT: #{feed_url}")
        {:ok, cached_xml}

      :miss ->
        Logger.debug("RSS cache MISS: #{feed_url}")

        case fetch_from_url(feed_url) do
          {:ok, xml} ->
            put(cache_key, xml)
            {:ok, xml}

          error ->
            error
        end
    end
  end

  @doc """
  Récupère depuis le cache
  """
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, value}
      {:error, _} -> :miss
    end
  end

  @doc """
  Met en cache avec TTL
  """
  def put(key, value) do
    Cachex.put(@cache_name, key, value, ttl: @cache_ttl)
  end

  @doc """
  Fetch et parse un flux RSS, retournant à la fois le metadata et les épisodes.

  Utilise le cache à deux niveaux: XML et métadonnées parsées.
  """
  def fetch_and_parse_feed(feed_url) do
    with {:ok, xml} <- fetch_feed(feed_url),
         {:ok, metadata} <- RssParser.parse_feed(xml),
         {:ok, episodes} <- RssParser.parse_episodes(xml) do
      {:ok, {metadata, episodes}}
    end
  end

  @doc """
  Récupère les métadonnées parsées d'un flux RSS depuis le cache ou en fetchant.

  Les métadonnées sont cachées séparément du XML brut pour un accès rapide.
  """
  def get_feed_metadata(feed_url) do
    cache_key = {:metadata, feed_url}

    case get(cache_key) do
      {:ok, cached_metadata} ->
        Logger.debug("Metadata cache HIT: #{feed_url}")
        {:ok, cached_metadata}

      :miss ->
        Logger.debug("Metadata cache MISS: #{feed_url}")

        case fetch_and_parse_feed(feed_url) do
          {:ok, {metadata, _episodes}} ->
            put(cache_key, metadata)
            {:ok, metadata}

          error ->
            error
        end
    end
  end

  # Fetch HTTP d'un flux RSS with SSRF protection
  defp fetch_from_url(url) do
    # Validate URL before fetching to prevent SSRF attacks
    case UrlValidator.validate_rss_url(url) do
      :ok ->
        do_fetch(url)

      {:error, reason} ->
        Logger.warning("RSS fetch blocked by URL validation: #{reason} for #{url}")
        {:error, :url_blocked}
    end
  end

  defp do_fetch(url) do
    case HTTPoison.get(url, [], follow_redirect: true, timeout: 10_000, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("RSS fetch failed with status #{status}: #{url}")
        {:error, :fetch_failed}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("RSS fetch error: #{inspect(reason)}")
        {:error, :fetch_failed}
    end
  end
end
