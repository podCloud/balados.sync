defmodule BaladosSyncJobs.SnapshotWorker do
  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Commands.Snapshot
  alias BaladosSyncProjections.ProjectionsRepo

  @forty_five_days_ago_seconds 45 * 24 * 60 * 60
  @thirty_one_days_ago_seconds 31 * 24 * 60 * 60

  def perform do
    Logger.info("Starting snapshot worker...")

    # Récupérer tous les événements de plus de 45 jours
    forty_five_days_ago = DateTime.add(DateTime.utc_now(), -@forty_five_days_ago_seconds, :second)

    old_events = get_old_events(forty_five_days_ago)

    # Grouper par user_id
    events_by_user = Enum.group_by(old_events, & &1.user_id)

    Logger.info("Found #{map_size(events_by_user)} users with events older than 45 days")

    # Pour chaque user, créer un checkpoint
    Enum.each(events_by_user, fn {user_id, _events} ->
      create_user_checkpoint(user_id, true)
    end)

    # Recalculer la popularité pour tous les podcasts/épisodes affectés
    recalculate_popularity()

    Logger.info("Snapshot worker completed")
  end

  defp get_old_events(cutoff_date) do
    # Query EventStore pour récupérer les vieux events
    # TODO: Ceci est une simplification - EventStore a sa propre API
    #
    query = """
    SELECT 
      data->>'user_id' as user_id,
      event_type,
      data->>'rss_source_feed' as feed,
      data->>'rss_source_item' as item
    FROM events.events
    WHERE created_at < $1
    AND event_type IN (
      'Elixir.BaladosSyncCore.Events.UserSubscribed',
      'Elixir.BaladosSyncCore.Events.PlayRecorded',
      'Elixir.BaladosSyncCore.Events.EpisodeSaved'
    )
    """

    # Execute raw query - à adapter selon votre EventStore
    # TODO: Adapter selon EventStore
    {:ok, result} = Ecto.Adapters.SQL.query(Repo, query, [cutoff_date])

    Enum.map(result.rows, fn [user_id, event_type, feed, item] ->
      %{user_id: user_id, event_type: event_type, feed: feed, item: item}
    end)
  end

  defp create_user_checkpoint(user_id, cleanup_old_events) do
    Logger.info("Creating checkpoint for user #{user_id}")

    command = %Snapshot{
      user_id: user_id,
      cleanup_old_events: cleanup_old_events
    }

    case BaladosSyncCore.Dispatcher.dispatch(command, consistency: :strong) do
      :ok ->
        Logger.info("Checkpoint created for user #{user_id}")

        # Si cleanup activé, supprimer les events > 31j après le checkpoint
        if cleanup_old_events do
          cleanup_old_user_events(user_id)
        end

      {:error, reason} ->
        Logger.error("Failed to create checkpoint for user #{user_id}: #{inspect(reason)}")
    end
  end

  defp cleanup_old_user_events(user_id) do
    thirty_one_days_ago = DateTime.add(DateTime.utc_now(), -@thirty_one_days_ago_seconds, :second)

    # Supprimer les events de plus de 31 jours pour cet user
    # TODO: EventStore peut avoir sa propre API de suppression
    query = """
    DELETE FROM events.events
    WHERE data->>'user_id' = $1
    AND created_at < $2
    """

    case Ecto.Adapters.SQL.query(Repo, query, [user_id, thirty_one_days_ago]) do
      {:ok, result} ->
        Logger.info("Cleaned up #{result.num_rows} old events for user #{user_id}")

      {:error, reason} ->
        Logger.error("Failed to cleanup events for user #{user_id}: #{inspect(reason)}")
    end
  end

  defp recalculate_popularity do
    Logger.info("Recalculating popularity...")

    # Récupérer tous les podcasts et épisodes depuis public_events
    feeds = get_distinct_feeds()
    items = get_distinct_items()

    # Pour chaque feed, calculer la nouvelle popularité
    Enum.each(feeds, fn feed ->
      calculate_feed_popularity(feed)
    end)

    # Pour chaque item, calculer la nouvelle popularité
    Enum.each(items, fn item ->
      calculate_item_popularity(item)
    end)
  end

  defp get_distinct_feeds do
    query =
      from(pe in "public.public_events",
        where: not is_nil(pe.rss_source_feed),
        distinct: true,
        select: pe.rss_source_feed
      )

    ProjectionsRepo.all(query)
  end

  defp get_distinct_items do
    query =
      from(pe in "public.public_events",
        where: not is_nil(pe.rss_source_item),
        distinct: true,
        select: %{feed: pe.rss_source_feed, item: pe.rss_source_item}
      )

    ProjectionsRepo.all(query)
  end

  defp calculate_feed_popularity(feed) do
    # Scores: subscribe=10, play=5, save/like=3, share=2
    query =
      from(pe in "public.public_events",
        where: pe.rss_source_feed == ^feed,
        select: %{
          event_type: pe.event_type,
          count: count(pe.id)
        },
        group_by: pe.event_type
      )

    results = ProjectionsRepo.all(query)

    total_score =
      Enum.reduce(results, 0, fn %{event_type: type, count: count}, acc ->
        score =
          case type do
            "subscribe" -> 10
            "play" -> 5
            "save" -> 3
            "share" -> 2
            _ -> 0
          end

        acc + score * count
      end)

    # Mettre à jour podcast_popularity
    from(p in "public.podcast_popularity", where: p.rss_source_feed == ^feed)
    |> ProjectionsRepo.update_all(
      set: [
        plays_previous: total_score,
        updated_at: DateTime.utc_now()
      ]
    )

    Logger.debug("Feed #{feed} popularity: #{total_score}")
  end

  defp calculate_item_popularity(%{feed: _feed, item: item}) do
    query =
      from(pe in "public.public_events",
        where: pe.rss_source_item == ^item,
        select: %{
          event_type: pe.event_type,
          count: count(pe.id)
        },
        group_by: pe.event_type
      )

    results = ProjectionsRepo.all(query)

    total_score =
      Enum.reduce(results, 0, fn %{event_type: type, count: count}, acc ->
        score =
          case type do
            "play" -> 5
            "save" -> 3
            "share" -> 2
            _ -> 0
          end

        acc + score * count
      end)

    # Mettre à jour episode_popularity
    from(e in "public.episode_popularity", where: e.rss_source_item == ^item)
    |> ProjectionsRepo.update_all(
      set: [
        plays_previous: total_score,
        updated_at: DateTime.utc_now()
      ]
    )

    Logger.debug("Item #{item} popularity: #{total_score}")
  end
end
