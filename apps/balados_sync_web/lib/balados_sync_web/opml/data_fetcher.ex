defmodule BaladosSyncWeb.Opml.DataFetcher do
  @moduledoc """
  Fetches user data from the database and converts to OPML structures.
  """

  import Ecto.Query

  alias BaladosSyncProjections.ProjectionsRepo

  alias BaladosSyncProjections.Schemas.{
    Subscription,
    PlayStatus,
    Playlist,
    PlaylistItem,
    Collection,
    UserPrivacy
  }

  alias BaladosSyncCore.RssCache
  alias BaladosSyncWeb.Opml
  alias BaladosSyncWeb.Opml.Document

  @doc """
  Fetch all user data and convert to OPML Document structure.

  ## Options

  - `:include_metadata` - Fetch RSS metadata for titles (default: true)
  """
  def fetch(user_id, opts \\ []) do
    include_metadata = Keyword.get(opts, :include_metadata, true)

    subscriptions = fetch_subscriptions(user_id, include_metadata)
    playlists = fetch_playlists(user_id)
    collections = fetch_collections(user_id)

    %Document{
      title: nil,
      date_created: DateTime.utc_now(),
      version: Opml.version(),
      subscriptions: subscriptions,
      playlists: playlists,
      collections: collections
    }
  end

  # ===== Subscriptions =====

  defp fetch_subscriptions(user_id, include_metadata) do
    # Fetch raw data
    db_subscriptions = fetch_db_subscriptions(user_id)
    play_statuses = fetch_db_play_statuses(user_id)
    privacy_settings = fetch_db_privacy_settings(user_id)

    # Group play statuses by feed
    play_statuses_by_feed = Enum.group_by(play_statuses, & &1.rss_source_feed)

    # Map privacy settings by feed
    privacy_by_feed =
      privacy_settings
      |> Enum.filter(&(&1.rss_source_item == ""))
      |> Enum.into(%{}, fn p -> {p.rss_source_feed, p.privacy} end)

    # Convert to OPML structures
    db_subscriptions
    |> Enum.map(fn sub ->
      feed_url = decode_feed_url(sub.rss_source_feed)
      title = get_title(sub, feed_url, include_metadata)
      play_statuses = Map.get(play_statuses_by_feed, sub.rss_source_feed, [])
      privacy = Map.get(privacy_by_feed, sub.rss_source_feed, "public")

      %Opml.Subscription{
        feed_url: feed_url,
        title: title,
        subscribed_at: sub.subscribed_at,
        unsubscribed_at: sub.unsubscribed_at,
        privacy: privacy,
        source_id: sub.rss_source_id,
        play_statuses: Enum.map(play_statuses, &convert_play_status/1)
      }
    end)
    |> Enum.reject(fn sub -> is_nil(sub.feed_url) end)
  end

  defp fetch_db_subscriptions(user_id) do
    from(s in Subscription,
      where: s.user_id == ^user_id,
      where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at,
      order_by: [desc: s.subscribed_at]
    )
    |> ProjectionsRepo.all()
  end

  defp fetch_db_play_statuses(user_id) do
    from(ps in PlayStatus,
      where: ps.user_id == ^user_id,
      order_by: [desc: ps.updated_at]
    )
    |> ProjectionsRepo.all()
  end

  defp fetch_db_privacy_settings(user_id) do
    from(p in UserPrivacy,
      where: p.user_id == ^user_id
    )
    |> ProjectionsRepo.all()
  end

  defp convert_play_status(ps) do
    %Opml.PlayStatus{
      guid: extract_guid(ps),
      position: ps.position || 0,
      played: ps.played || false,
      updated_at: ps.updated_at
    }
  end

  defp extract_guid(play_status) do
    case Base.url_decode64(play_status.rss_source_item || "", padding: false) do
      {:ok, decoded} ->
        case String.split(decoded, ",") do
          [_feed, guid | _rest] when guid != "" -> guid
          _ -> generate_fallback_guid(play_status)
        end

      _ ->
        generate_fallback_guid(play_status)
    end
  end

  defp generate_fallback_guid(play_status) do
    if play_status.rss_enclosure && play_status.rss_enclosure != "" do
      play_status.rss_enclosure
    else
      Opml.generate_fallback_guid(
        play_status.rss_source_feed || "",
        play_status.rss_source_item || ""
      )
    end
  end

  # ===== Playlists =====

  defp fetch_playlists(user_id) do
    from(p in Playlist,
      where: p.user_id == ^user_id,
      where: is_nil(p.deleted_at),
      order_by: [desc: p.updated_at],
      preload: [
        items: ^from(i in PlaylistItem, where: is_nil(i.deleted_at), order_by: i.position)
      ]
    )
    |> ProjectionsRepo.all()
    |> Enum.map(&convert_playlist/1)
  end

  defp convert_playlist(playlist) do
    %Opml.Playlist{
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      type: playlist.type || "playlist",
      is_public: playlist.is_public || false,
      updated_at: playlist.updated_at,
      items: Enum.map(playlist.items || [], &convert_playlist_item/1)
    }
  end

  defp convert_playlist_item(item) do
    %Opml.PlaylistItem{
      feed_url: decode_feed_url(item.rss_source_feed),
      guid: extract_item_guid(item),
      position: item.position || 0,
      item_title: item.item_title,
      feed_title: item.feed_title
    }
  end

  defp extract_item_guid(item) do
    case Base.url_decode64(item.rss_source_item || "", padding: false) do
      {:ok, decoded} ->
        case String.split(decoded, ",") do
          [_feed, guid | _rest] when guid != "" -> guid
          _ -> generate_item_fallback_guid(item)
        end

      _ ->
        generate_item_fallback_guid(item)
    end
  end

  defp generate_item_fallback_guid(item) do
    Opml.generate_fallback_guid(
      item.rss_source_feed || "",
      item.rss_source_item || ""
    )
  end

  # ===== Collections =====

  defp fetch_collections(user_id) do
    from(c in Collection,
      where: c.user_id == ^user_id,
      where: is_nil(c.deleted_at),
      order_by: [desc: c.updated_at],
      preload: [:collection_subscriptions]
    )
    |> ProjectionsRepo.all()
    |> Enum.map(&convert_collection/1)
  end

  defp convert_collection(collection) do
    feeds =
      (collection.collection_subscriptions || [])
      |> Enum.map(fn cs -> decode_feed_url(cs.rss_source_feed) end)
      |> Enum.reject(&is_nil/1)

    %Opml.Collection{
      id: collection.id,
      title: collection.title,
      description: collection.description,
      is_public: collection.is_public || false,
      color: collection.color,
      updated_at: collection.updated_at,
      feeds: feeds
    }
  end

  # ===== Helpers =====

  defp decode_feed_url(nil), do: nil

  defp decode_feed_url(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp get_title(sub, feed_url, include_metadata) do
    cond do
      sub.rss_feed_title && sub.rss_feed_title != "" ->
        sub.rss_feed_title

      include_metadata && feed_url ->
        case RssCache.get_feed_metadata(feed_url) do
          {:ok, meta} -> meta.title
          _ -> "Unknown Podcast"
        end

      true ->
        "Unknown Podcast"
    end
  end
end
