defmodule BaladosSyncWeb.PlaylistEnricher do
  @moduledoc """
  Enriches playlist items with metadata fetched from RSS feeds.

  Fetches RSS feeds in parallel and matches episodes with playlist items
  to provide enriched metadata (full description, cover, pub_date, duration, etc.).
  """

  require Logger
  alias BaladosSyncCore.RssCache

  @feed_timeout 5_000
  @max_concurrency 5

  @doc """
  Enriches a list of playlist items with metadata from their source RSS feeds.

  ## Process

  1. Groups items by source feed URL
  2. Fetches each feed in parallel with timeout protection
  3. Matches parsed episodes with playlist items by GUID
  4. Returns enriched items with additional metadata

  ## Returns

  A list of enriched items, each containing:
  - Original item fields (id, position, etc.)
  - Enriched fields: :description, :cover, :pub_date, :duration, :enclosure, :link
  - :enriched flag (true if metadata was fetched, false if using fallback)

  ## Example

      iex> items = [%{rss_source_feed: "https://...", rss_source_item: "ep-123", ...}]
      iex> enriched = PlaylistEnricher.enrich_items(items)
      iex> hd(enriched).enriched
      true
  """
  def enrich_items([]), do: []

  def enrich_items(items) when is_list(items) do
    # Group items by feed URL
    items_by_feed = Enum.group_by(items, & &1.rss_source_feed)

    # Fetch all feeds in parallel
    feed_episodes = fetch_feeds_parallel(Map.keys(items_by_feed))

    # Enrich each item with fetched metadata
    Enum.map(items, fn item ->
      enrich_item(item, feed_episodes)
    end)
  end

  @doc """
  Fetches multiple RSS feeds in parallel with timeout protection.

  Returns a map of %{feed_url => %{guid => episode_metadata}}.
  """
  def fetch_feeds_parallel(feed_urls) when is_list(feed_urls) do
    feed_urls
    |> Task.async_stream(
      &fetch_and_index_feed/1,
      max_concurrency: @max_concurrency,
      timeout: @feed_timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn result, acc ->
      case result do
        {:ok, {feed_url, episodes_map}} ->
          Map.put(acc, feed_url, episodes_map)

        {:exit, :timeout} ->
          Logger.warning("Feed fetch timeout, using cached metadata")
          acc

        {:exit, reason} ->
          Logger.warning("Feed fetch failed: #{inspect(reason)}")
          acc
      end
    end)
  end

  # Fetches a single feed and indexes episodes by GUID
  defp fetch_and_index_feed(feed_url) do
    case RssCache.fetch_and_parse_feed(feed_url) do
      {:ok, {_metadata, episodes}} ->
        # Index episodes by GUID for O(1) lookup
        episodes_map =
          episodes
          |> Enum.reduce(%{}, fn episode, acc ->
            Map.put(acc, episode.guid, episode)
          end)

        {feed_url, episodes_map}

      {:error, reason} ->
        Logger.warning("Failed to fetch feed #{feed_url}: #{inspect(reason)}")
        {feed_url, %{}}
    end
  end

  # Enriches a single item with metadata from fetched feeds
  defp enrich_item(item, feed_episodes) do
    feed_url = item.rss_source_feed
    item_guid = item.rss_source_item

    episodes_map = Map.get(feed_episodes, feed_url, %{})
    episode = Map.get(episodes_map, item_guid)

    if episode do
      %{
        # Original item data
        id: item.id,
        user_id: item.user_id,
        playlist_id: item.playlist_id,
        rss_source_feed: item.rss_source_feed,
        rss_source_item: item.rss_source_item,
        position: item.position,
        # Prefer enriched data, fallback to stored data
        item_title: episode.title || item.item_title,
        feed_title: item.feed_title,
        # New enriched fields
        description: episode.description,
        cover: episode.cover,
        pub_date: episode.pub_date,
        pub_date_raw: episode.pub_date_raw,
        duration: episode.duration,
        enclosure: episode.enclosure,
        link: episode.link,
        author: episode.author,
        # Flag indicating enrichment success
        enriched: true
      }
    else
      # Fallback: keep original data without enrichment
      %{
        id: item.id,
        user_id: item.user_id,
        playlist_id: item.playlist_id,
        rss_source_feed: item.rss_source_feed,
        rss_source_item: item.rss_source_item,
        position: item.position,
        item_title: item.item_title,
        feed_title: item.feed_title,
        # Empty enriched fields
        description: nil,
        cover: nil,
        pub_date: nil,
        pub_date_raw: nil,
        duration: nil,
        enclosure: nil,
        link: nil,
        author: nil,
        enriched: false
      }
    end
  end

  @doc """
  Formats duration in seconds to human-readable format (HH:MM:SS or MM:SS).
  """
  def format_duration(nil), do: nil

  def format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
    else
      "#{minutes}:#{String.pad_leading(to_string(secs), 2, "0")}"
    end
  end

  def format_duration(_), do: nil

  @doc """
  Formats pub_date to a relative or absolute date string.
  """
  def format_pub_date(nil), do: nil

  def format_pub_date(%DateTime{} = date) do
    now = DateTime.utc_now()
    diff_days = DateTime.diff(now, date, :day)

    cond do
      diff_days == 0 -> "Today"
      diff_days == 1 -> "Yesterday"
      diff_days < 7 -> "#{diff_days} days ago"
      diff_days < 30 -> "#{div(diff_days, 7)} weeks ago"
      diff_days < 365 -> "#{div(diff_days, 30)} months ago"
      true -> Calendar.strftime(date, "%b %d, %Y")
    end
  end

  def format_pub_date(_), do: nil

  @doc """
  Strips HTML tags from a string.
  """
  def strip_html_tags(nil), do: ""

  def strip_html_tags(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def strip_html_tags(_), do: ""
end
