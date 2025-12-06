defmodule BaladosSyncWeb.Queries do
  import Ecto.Query
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Subscription, PlayStatus, Playlist, PlaylistItem}

  def get_user_subscriptions(user_id) do
    from(s in Subscription,
      where: s.user_id == ^user_id,
      where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at,
      order_by: [desc: s.subscribed_at]
    )
    |> ProjectionsRepo.all()
    |> Enum.map(&format_subscription/1)
  end

  def get_user_play_statuses(user_id) do
    from(ps in PlayStatus,
      where: ps.user_id == ^user_id,
      order_by: [desc: ps.updated_at]
    )
    |> ProjectionsRepo.all()
    |> Enum.map(&format_play_status/1)
  end

  def get_user_playlists(user_id) do
    playlists =
      from(p in Playlist,
        where: p.user_id == ^user_id,
        order_by: [desc: p.updated_at],
        preload: [items: ^active_playlist_items_query()]
      )
      |> ProjectionsRepo.all()

    Enum.map(playlists, &format_playlist/1)
  end

  defp active_playlist_items_query do
    from(pi in PlaylistItem,
      where: is_nil(pi.deleted_at),
      order_by: [asc: pi.inserted_at]
    )
  end

  defp format_subscription(sub) do
    %{
      rss_source_feed: sub.rss_source_feed,
      rss_source_id: sub.rss_source_id,
      rss_feed_title: sub.rss_feed_title,
      subscribed_at: sub.subscribed_at,
      unsubscribed_at: sub.unsubscribed_at
    }
  end

  defp format_play_status(ps) do
    %{
      rss_source_feed: ps.rss_source_feed,
      rss_source_item: ps.rss_source_item,
      rss_feed_title: ps.rss_feed_title,
      rss_item_title: ps.rss_item_title,
      played: ps.played,
      position: ps.position,
      rss_enclosure: ps.rss_enclosure,
      updated_at: ps.updated_at
    }
  end

  defp format_playlist(playlist) do
    %{
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      updated_at: playlist.updated_at,
      items: Enum.map(playlist.items, &format_playlist_item/1)
    }
  end

  defp format_playlist_item(item) do
    %{
      id: item.id,
      rss_source_feed: item.rss_source_feed,
      rss_source_item: item.rss_source_item,
      item_title: item.item_title,
      feed_title: item.feed_title,
      created_at: item.inserted_at
    }
  end

  @doc """
  Check if a user is subscribed to a specific feed.
  Returns true if subscribed, false otherwise.
  """
  def is_user_subscribed?(user_id, encoded_feed) do
    from(s in Subscription,
      where: s.user_id == ^user_id and s.rss_source_feed == ^encoded_feed,
      where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at,
      select: s.id
    )
    |> ProjectionsRepo.one()
    |> case do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Get subscription details for a user and feed.
  Returns the subscription record or nil if not subscribed.
  """
  def get_user_subscription(user_id, encoded_feed) do
    from(s in Subscription,
      where: s.user_id == ^user_id and s.rss_source_feed == ^encoded_feed,
      where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at
    )
    |> ProjectionsRepo.one()
  end
end
