defmodule BaladosSyncJobs.SnapshotWorker do
  @moduledoc """
  Worker that creates periodic checkpoints for users with old events
  and cleans up events older than the retention period.

  Dispatches per-aggregate snapshot commands (SnapshotSubscription,
  SnapshotPlayTracking, SnapshotPlaylist, SnapshotCollection) for each user
  with old events.

  Uses EventStore's native API (`read_all_streams_forward/3`) for reading events
  instead of raw SQL queries. Event cleanup still uses raw SQL as the EventStore
  library does not provide a native API for deleting individual events.
  """

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Commands.{SnapshotSubscription, SnapshotPlayTracking, SnapshotPlaylist, SnapshotCollection}
  alias BaladosSyncProjections.ProjectionsRepo

  @doc "Returns the dispatcher module (configurable for testing)."
  def dispatcher do
    Application.get_env(:balados_sync_jobs, :dispatcher, BaladosSyncCore.Dispatcher)
  end

  @forty_five_days_ago_seconds 45 * 24 * 60 * 60
  @thirty_one_days_ago_seconds 31 * 24 * 60 * 60
  @batch_size 1000

  @target_event_types MapSet.new([
                        "Elixir.BaladosSyncCore.Events.UserSubscribed",
                        "Elixir.BaladosSyncCore.Events.PlayRecorded",
                        "Elixir.BaladosSyncCore.Events.EpisodeSaved"
                      ])

  @doc """
  Returns the EventStore module to use. Configurable via application env
  for testability. Defaults to `BaladosSyncCore.EventStore`.
  """
  def event_store do
    Application.get_env(:balados_sync_jobs, :event_store, BaladosSyncCore.EventStore)
  end

  def perform do
    Logger.info("Starting snapshot worker...")

    forty_five_days_ago =
      DateTime.add(DateTime.utc_now(), -@forty_five_days_ago_seconds, :second)

    old_events = get_old_events(forty_five_days_ago)

    events_by_user = Enum.group_by(old_events, & &1.user_id)

    Logger.info("Found #{map_size(events_by_user)} users with events older than 45 days")

    Enum.each(events_by_user, fn {user_id, _events} ->
      create_user_checkpoints(user_id, true)
    end)

    recalculate_popularity()

    Logger.info("Snapshot worker completed")
  end

  @doc """
  Reads old events from the EventStore using the native API with pagination.

  Uses `read_all_streams_forward/3` to iterate through events in batches,
  filtering by cutoff date and target event types. Events are read in
  chronological order (by event_number), and reading stops when events
  newer than the cutoff date are encountered.
  """
  def get_old_events(cutoff_date) do
    case read_events_before(cutoff_date, 0, []) do
      {:ok, events} -> events
      {:error, reason} ->
        Logger.warning("Returning empty results due to EventStore error: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Filters a list of RecordedEvent structs, keeping only events that are
  older than `cutoff_date` and match the target event types.

  Returns a list of maps with `:user_id`, `:event_type`, `:feed`, and `:item` keys.

  This is a pure function extracted for testability.
  """
  def filter_events(events, cutoff_date) do
    events
    |> Enum.filter(fn event ->
      DateTime.compare(event.created_at, cutoff_date) == :lt and
        MapSet.member?(@target_event_types, event.event_type)
    end)
    |> Enum.map(&extract_event_data/1)
  end

  @doc """
  Returns the set of event types that the snapshot worker targets.
  """
  def target_event_types, do: @target_event_types

  defp extract_event_data(event) do
    %{
      user_id: get_event_field(event.data, :user_id),
      event_type: event.event_type,
      feed: get_event_field(event.data, :rss_source_feed),
      item: get_event_field(event.data, :rss_source_item)
    }
  end

  defp get_event_field(data, field) when is_struct(data), do: Map.get(data, field)
  defp get_event_field(data, field) when is_map(data), do: Map.get(data, field)
  defp get_event_field(_data, _field), do: nil

  defp read_events_before(cutoff_date, start_from, acc) do
    case event_store().read_all_streams_forward(start_from, @batch_size) do
      {:ok, []} ->
        {:ok, Enum.reverse(acc)}

      {:ok, events} ->
        last_event = List.last(events)
        filtered = filter_events(events, cutoff_date)
        new_acc = Enum.reverse(filtered) ++ acc

        # Always continue reading to avoid missing out-of-order events
        # (event_number order may not match created_at order)
        next_position = last_event.event_number + 1
        read_events_before(cutoff_date, next_position, new_acc)

      {:error, reason} ->
        Logger.error("Failed to read events from EventStore: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Public for testability only. Not part of the public API — call perform/0 instead.
  @doc false
  def create_user_checkpoints(user_id, cleanup_old_events) do
    Logger.info("Creating checkpoints for user #{user_id}")

    # Dispatch per-aggregate snapshot commands.
    # All snapshots must succeed before old events are cleaned up (all-or-nothing per user).
    # This is intentional: partial cleanup could leave some aggregates without the events
    # they need to rebuild state. If one aggregate fails, no events are deleted, and
    # the next scheduled run will retry all snapshots for this user.
    commands = [
      %SnapshotSubscription{user_id: user_id},
      %SnapshotPlayTracking{user_id: user_id},
      %SnapshotPlaylist{user_id: user_id},
      %SnapshotCollection{user_id: user_id}
    ]

    # Dispatch all 4 checkpoint commands without short-circuiting.
    # Even if one fails, we dispatch the rest — cleanup is only performed
    # when all succeed, so partial snapshots are harmless. Dispatching all
    # commands lets us report every failure in a single pass rather than
    # masking subsequent failures behind the first one.
    results =
      Enum.map(commands, fn command ->
        {command, dispatcher().dispatch(command, consistency: :strong)}
      end)

    failures =
      Enum.filter(results, fn {_cmd, result} -> result != :ok end)

    if failures == [] do
      Logger.info("Checkpoints created for user #{user_id}")

      if cleanup_old_events do
        cleanup_old_user_events(user_id)
      end
    else
      Enum.each(failures, fn {cmd, error} ->
        Logger.error(
          "Failed checkpoint #{inspect(cmd.__struct__)} for user #{user_id}: #{inspect(error)}"
        )
      end)
    end
  end

  defp cleanup_old_user_events(user_id) do
    thirty_one_days_ago =
      DateTime.add(DateTime.utc_now(), -@thirty_one_days_ago_seconds, :second)

    # Raw SQL is required here because the EventStore library does not provide
    # a native API for deleting individual events from a stream. The only native
    # option is `delete_stream/4` which removes the entire stream, but we need
    # to keep recent events and the checkpoint event.
    query = """
    DELETE FROM events.events
    WHERE data->>'user_id' = $1
    AND created_at < $2
    """

    case Ecto.Adapters.SQL.query(event_store(), query, [user_id, thirty_one_days_ago]) do
      {:ok, result} ->
        Logger.info("Cleaned up #{result.num_rows} old events for user #{user_id}")

      {:error, reason} ->
        Logger.error("Failed to cleanup events for user #{user_id}: #{inspect(reason)}")
    end
  end

  defp recalculate_popularity do
    Logger.info("Recalculating popularity...")

    feeds = get_distinct_feeds()
    items = get_distinct_items()

    Enum.each(feeds, fn feed ->
      calculate_feed_popularity(feed)
    end)

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
