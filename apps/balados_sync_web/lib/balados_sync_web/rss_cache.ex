defmodule BaladosSyncWeb.RssCache do
  @moduledoc """
  Module de cache borné (500 entrées, éviction LRW) pour les flux RSS avec TTL de 5 minutes
  """
  require Logger
  alias BaladosSyncCore.SafeHttp

  @cache_name :rss_feed_cache
  @cache_ttl :timer.minutes(5)

  @doc """
  Récupère un flux RSS, depuis le cache ou en le fetchant
  """
  def fetch_feed(feed_url) do
    cache_key = {:feed, feed_url}

    case get(cache_key) do
      {:ok, cached_xml} ->
        Logger.debug("RSS cache HIT: #{SafeHttp.loggable(feed_url)}")
        {:ok, cached_xml}

      :miss ->
        Logger.debug("RSS cache MISS: #{SafeHttp.loggable(feed_url)}")

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
    Cachex.put(@cache_name, key, value, expire: @cache_ttl)
  end

  @doc """
  Fetch et parse un flux RSS, retournant à la fois le XML brut et les métadonnées parsées.

  Utilise le cache à deux niveaux: XML et métadonnées parsées.
  """
  def fetch_and_parse_feed(feed_url) do
    with {:ok, xml} <- fetch_feed(feed_url),
         {:ok, metadata} <- BaladosSyncWeb.RssParser.parse_feed(xml) do
      {:ok, %{xml: xml, metadata: metadata}}
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
        Logger.debug("Metadata cache HIT: #{SafeHttp.loggable(feed_url)}")
        {:ok, cached_metadata}

      :miss ->
        Logger.debug("Metadata cache MISS: #{SafeHttp.loggable(feed_url)}")

        case fetch_and_parse_feed(feed_url) do
          {:ok, %{metadata: metadata}} ->
            put(cache_key, metadata)
            {:ok, metadata}

          error ->
            error
        end
    end
  end

  # Fetch HTTP d'un flux RSS : SafeHttp valide l'URL et chaque redirection (SSRF)
  defp fetch_from_url(url) do
    case SafeHttp.get(url) do
      {:ok, body} ->
        {:ok, body}

      {:error, :url_blocked} ->
        Logger.warning("RSS fetch blocked by URL validation for #{SafeHttp.loggable(url)}")
        {:error, :url_blocked}

      {:error, {:http_error, status}} ->
        Logger.error("RSS fetch failed with status #{status}: #{SafeHttp.loggable(url)}")
        {:error, :fetch_failed}

      {:error, reason} ->
        Logger.error("RSS fetch error: #{inspect(reason)}")
        {:error, :fetch_failed}
    end
  end
end
