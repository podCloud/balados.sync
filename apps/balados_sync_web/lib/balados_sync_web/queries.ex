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

  @doc """
  Get user playlists, optionally filtered by type.

  Options:
  - `:type` - Filter by playlist type ("playlist" or "queue"). Default: "playlist"
  - `:include_all_types` - If true, returns all types. Default: false
  """
  def get_user_playlists(user_id, opts \\ []) do
    include_all = Keyword.get(opts, :include_all_types, false)
    type_filter = Keyword.get(opts, :type, "playlist")

    query =
      from(p in Playlist,
        where: p.user_id == ^user_id,
        where: is_nil(p.deleted_at),
        order_by: [desc: p.updated_at],
        preload: [items: ^active_playlist_items_query()]
      )

    query =
      if include_all do
        query
      else
        from(p in query, where: p.type == ^type_filter)
      end

    query
    |> ProjectionsRepo.all()
    |> Enum.map(&format_playlist/1)
  end

  @doc """
  Get user queues (device playback queues).
  """
  def get_user_queues(user_id) do
    get_user_playlists(user_id, type: "queue")
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
      type: playlist.type || "playlist",
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
  Get paginated listening history for a user with optional filters.

  Options:
  - `:page` - Page number (1-based). Default: 1
  - `:per_page` - Items per page. Default: 50
  - `:feed` - Filter by rss_source_feed (base64url-encoded). Default: nil (all feeds)
  - `:period` - Filter by time period: "week", "month", "year". Default: nil (all time)
  - `:status` - Filter by status: "completed", "in_progress", "not_started". Default: nil (all)

  Returns `{entries, total_count}`.
  """
  def get_listening_history(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset = (page - 1) * per_page

    base = listening_history_base_query(user_id, opts)

    entries =
      from(ps in base,
        order_by: [desc: ps.updated_at],
        limit: ^per_page,
        offset: ^offset
      )
      |> ProjectionsRepo.all()
      |> Enum.map(&format_play_status/1)

    total =
      from(ps in base, select: count(ps.id))
      |> ProjectionsRepo.one()

    {entries, total}
  end

  @doc """
  Get listening history stats for a user (async-loaded in LiveView).

  Returns a map with:
  - `:total_time` - Total listening time in seconds (sum of positions)
  - `:total_episodes` - Total episodes with any activity
  - `:completed_count` - Number of completed episodes
  - `:streak_days` - Consecutive days of listening (based on updated_at event timestamp)
  - `:top_podcasts` - Top 5 podcasts by episode count [{feed_title, count}]
  """
  def get_listening_stats(user_id) do
    base_query = from(ps in PlayStatus, where: ps.user_id == ^user_id)

    # Combine aggregates into a single query
    {total_time, total_episodes, completed_count} =
      from(ps in base_query,
        select: {
          coalesce(sum(ps.position), 0),
          count(ps.id),
          count(fragment("CASE WHEN ? = true THEN 1 END", ps.played))
        }
      )
      |> ProjectionsRepo.one()

    streak_days = compute_listening_streak(user_id)

    top_podcasts =
      from(ps in base_query,
        where: not is_nil(ps.rss_feed_title),
        group_by: [ps.rss_source_feed, ps.rss_feed_title],
        select: {ps.rss_feed_title, count(ps.id)},
        order_by: [desc: count(ps.id)],
        limit: 5
      )
      |> ProjectionsRepo.all()

    %{
      total_time: total_time,
      total_episodes: total_episodes,
      completed_count: completed_count,
      streak_days: streak_days,
      top_podcasts: top_podcasts
    }
  end

  @max_export_rows 10_000

  def max_export_rows, do: @max_export_rows

  @doc """
  Get listening history entries for export (capped at #{@max_export_rows} rows).

  Accepts the same filter options as `get_listening_history/2` except `:page` and `:per_page`.
  """
  def get_listening_history_export(user_id, opts \\ []) do
    listening_history_base_query(user_id, opts)
    |> order_by([ps], desc: ps.updated_at)
    |> limit(@max_export_rows)
    |> ProjectionsRepo.all()
    |> Enum.map(&format_play_status/1)
  end

  @doc """
  Get distinct feed titles for a user (for filter dropdown).
  """
  def get_user_feed_titles(user_id) do
    from(ps in PlayStatus,
      where: ps.user_id == ^user_id,
      where: not is_nil(ps.rss_feed_title),
      group_by: [ps.rss_source_feed, ps.rss_feed_title],
      select: {ps.rss_source_feed, ps.rss_feed_title},
      order_by: [asc: ps.rss_feed_title]
    )
    |> ProjectionsRepo.all()
  end

  defp listening_history_base_query(user_id, opts) do
    feed = Keyword.get(opts, :feed)
    period = Keyword.get(opts, :period)
    status = Keyword.get(opts, :status)

    query = from(ps in PlayStatus, where: ps.user_id == ^user_id)

    query =
      if feed && feed != "" do
        from(ps in query, where: ps.rss_source_feed == ^feed)
      else
        query
      end

    query =
      case period do
        "week" ->
          cutoff = DateTime.add(DateTime.utc_now(), -7, :day)
          from(ps in query, where: ps.updated_at >= ^cutoff)

        "month" ->
          cutoff = DateTime.add(DateTime.utc_now(), -30, :day)
          from(ps in query, where: ps.updated_at >= ^cutoff)

        "year" ->
          cutoff = DateTime.add(DateTime.utc_now(), -365, :day)
          from(ps in query, where: ps.updated_at >= ^cutoff)

        _ ->
          query
      end

    query =
      case status do
        "completed" ->
          from(ps in query, where: ps.played == true)

        "in_progress" ->
          from(ps in query, where: ps.played == false and ps.position > 0)

        "not_started" ->
          from(ps in query, where: ps.played == false and ps.position == 0)

        _ ->
          query
      end

    query
  end

  defp compute_listening_streak(user_id) do
    # Get distinct dates of activity, ordered descending
    # updated_at reflects the event timestamp from the domain (not Ecto auto-timestamp),
    # so it accurately represents when the user actually listened
    dates =
      from(ps in PlayStatus,
        where: ps.user_id == ^user_id,
        select: fragment("DISTINCT DATE(?)", ps.updated_at),
        order_by: [desc: fragment("DATE(?)", ps.updated_at)]
      )
      |> ProjectionsRepo.all()

    case dates do
      [] ->
        0

      [latest | rest] ->
        today = Date.utc_today()

        # Streak only counts if the latest activity is today or yesterday
        if Date.diff(today, latest) > 1 do
          0
        else
          count_consecutive_days([latest | rest], 1)
        end
    end
  end

  defp count_consecutive_days([_single], count), do: count

  defp count_consecutive_days([day1, day2 | rest], count) do
    if Date.diff(day1, day2) == 1 do
      count_consecutive_days([day2 | rest], count + 1)
    else
      count
    end
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
