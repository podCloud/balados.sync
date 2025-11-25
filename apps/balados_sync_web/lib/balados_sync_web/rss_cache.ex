defmodule BaladosSyncWeb.RssCache do
  @moduledoc """
  Module de cache LRU pour les flux RSS avec TTL de 5 minutes
  """
  require Logger

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

  # Fetch HTTP d'un flux RSS
  defp fetch_from_url(url) do
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
