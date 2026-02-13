defmodule BaladosSyncJobs.SnapshotWorkerTest do
  use ExUnit.Case, async: true

  alias BaladosSyncJobs.SnapshotWorker
  alias EventStore.RecordedEvent

  describe "filter_events/2" do
    test "filters events older than cutoff date with matching event types" do
      cutoff = ~U[2025-06-01 00:00:00Z]

      events = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: nil},
          created_at: ~U[2025-05-01 00:00:00Z]
        ),
        build_recorded_event(
          event_number: 2,
          event_type: "Elixir.BaladosSyncCore.Events.PlayRecorded",
          data: %{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-1"},
          created_at: ~U[2025-05-15 00:00:00Z]
        ),
        build_recorded_event(
          event_number: 3,
          event_type: "Elixir.BaladosSyncCore.Events.EpisodeSaved",
          data: %{user_id: "user-2", rss_source_feed: "feed-2", rss_source_item: "item-2"},
          created_at: ~U[2025-04-01 00:00:00Z]
        )
      ]

      result = SnapshotWorker.filter_events(events, cutoff)

      assert length(result) == 3
      assert Enum.at(result, 0).user_id == "user-1"
      assert Enum.at(result, 0).feed == "feed-1"
      assert Enum.at(result, 1).item == "item-1"
      assert Enum.at(result, 2).user_id == "user-2"
    end

    test "excludes events newer than cutoff date" do
      cutoff = ~U[2025-06-01 00:00:00Z]

      events = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-1", rss_source_feed: "feed-1"},
          created_at: ~U[2025-05-01 00:00:00Z]
        ),
        build_recorded_event(
          event_number: 2,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-2", rss_source_feed: "feed-2"},
          created_at: ~U[2025-07-01 00:00:00Z]
        )
      ]

      result = SnapshotWorker.filter_events(events, cutoff)

      assert length(result) == 1
      assert Enum.at(result, 0).user_id == "user-1"
    end

    test "excludes events with non-matching event types" do
      cutoff = ~U[2025-06-01 00:00:00Z]

      events = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-1", rss_source_feed: "feed-1"},
          created_at: ~U[2025-05-01 00:00:00Z]
        ),
        build_recorded_event(
          event_number: 2,
          event_type: "Elixir.BaladosSyncCore.Events.PrivacyChanged",
          data: %{user_id: "user-1"},
          created_at: ~U[2025-05-01 00:00:00Z]
        ),
        build_recorded_event(
          event_number: 3,
          event_type: "Elixir.BaladosSyncCore.Events.PlaylistCreated",
          data: %{user_id: "user-1"},
          created_at: ~U[2025-05-01 00:00:00Z]
        )
      ]

      result = SnapshotWorker.filter_events(events, cutoff)

      assert length(result) == 1
      assert Enum.at(result, 0).event_type == "Elixir.BaladosSyncCore.Events.UserSubscribed"
    end

    test "returns empty list when no events match" do
      cutoff = ~U[2025-01-01 00:00:00Z]

      events = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-1", rss_source_feed: "feed-1"},
          created_at: ~U[2025-06-01 00:00:00Z]
        )
      ]

      assert [] == SnapshotWorker.filter_events(events, cutoff)
    end

    test "handles empty event list" do
      cutoff = ~U[2025-06-01 00:00:00Z]
      assert [] == SnapshotWorker.filter_events([], cutoff)
    end

    test "handles struct data (deserialized events)" do
      cutoff = ~U[2025-06-01 00:00:00Z]

      event_data = %BaladosSyncCore.Events.UserSubscribed{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_id: "id-1",
        subscribed_at: ~U[2025-05-01 00:00:00Z],
        event_infos: %{device_id: "test", device_name: "Test"}
      }

      events = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: event_data,
          created_at: ~U[2025-05-01 00:00:00Z]
        )
      ]

      result = SnapshotWorker.filter_events(events, cutoff)

      assert length(result) == 1
      assert Enum.at(result, 0).user_id == "user-1"
      assert Enum.at(result, 0).feed == "feed-1"
    end

    test "handles events at exact cutoff boundary (excluded)" do
      cutoff = ~U[2025-06-01 00:00:00Z]

      events = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-1", rss_source_feed: "feed-1"},
          created_at: ~U[2025-06-01 00:00:00Z]
        )
      ]

      assert [] == SnapshotWorker.filter_events(events, cutoff)
    end
  end

  describe "target_event_types/0" do
    test "returns the expected event types" do
      types = SnapshotWorker.target_event_types()

      assert MapSet.member?(types, "Elixir.BaladosSyncCore.Events.UserSubscribed")
      assert MapSet.member?(types, "Elixir.BaladosSyncCore.Events.PlayRecorded")
      assert MapSet.member?(types, "Elixir.BaladosSyncCore.Events.EpisodeSaved")
      assert MapSet.size(types) == 3
    end
  end

  describe "event_store/0" do
    test "defaults to BaladosSyncCore.EventStore" do
      # Clear any test config
      original = Application.get_env(:balados_sync_jobs, :event_store)
      Application.delete_env(:balados_sync_jobs, :event_store)

      assert SnapshotWorker.event_store() == BaladosSyncCore.EventStore

      # Restore
      if original, do: Application.put_env(:balados_sync_jobs, :event_store, original)
    end

    test "can be configured via application env" do
      original = Application.get_env(:balados_sync_jobs, :event_store)
      Application.put_env(:balados_sync_jobs, :event_store, MyCustomEventStore)

      assert SnapshotWorker.event_store() == MyCustomEventStore

      # Restore
      if original do
        Application.put_env(:balados_sync_jobs, :event_store, original)
      else
        Application.delete_env(:balados_sync_jobs, :event_store)
      end
    end
  end

  describe "get_old_events/1 (integration with mock EventStore)" do
    setup do
      original = Application.get_env(:balados_sync_jobs, :event_store)

      on_exit(fn ->
        if original do
          Application.put_env(:balados_sync_jobs, :event_store, original)
        else
          Application.delete_env(:balados_sync_jobs, :event_store)
        end
      end)

      :ok
    end

    test "returns events from multiple batches (pagination)" do
      batch_1 =
        for i <- 1..3 do
          build_recorded_event(
            event_number: i,
            event_type: "Elixir.BaladosSyncCore.Events.PlayRecorded",
            data: %{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-#{i}"},
            created_at: ~U[2025-01-01 00:00:00Z]
          )
        end

      batch_2 =
        for i <- 4..5 do
          build_recorded_event(
            event_number: i,
            event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
            data: %{user_id: "user-2", rss_source_feed: "feed-#{i}"},
            created_at: ~U[2025-02-01 00:00:00Z]
          )
        end

      mock_module = define_mock_event_store([batch_1, batch_2])
      Application.put_env(:balados_sync_jobs, :event_store, mock_module)

      cutoff = ~U[2025-06-01 00:00:00Z]
      result = SnapshotWorker.get_old_events(cutoff)

      assert length(result) == 5
      # First batch: 3 PlayRecorded events
      assert Enum.count(result, &(&1.event_type == "Elixir.BaladosSyncCore.Events.PlayRecorded")) == 3
      # Second batch: 2 UserSubscribed events
      assert Enum.count(result, &(&1.event_type == "Elixir.BaladosSyncCore.Events.UserSubscribed")) == 2
    end

    test "returns empty list for empty event store" do
      mock_module = define_mock_event_store([])
      Application.put_env(:balados_sync_jobs, :event_store, mock_module)

      cutoff = ~U[2025-06-01 00:00:00Z]
      result = SnapshotWorker.get_old_events(cutoff)

      assert result == []
    end

    test "returns empty list on EventStore error" do
      mock_module = define_mock_event_store(:error)
      Application.put_env(:balados_sync_jobs, :event_store, mock_module)

      cutoff = ~U[2025-06-01 00:00:00Z]

      # Should gracefully return [] and not crash
      result = SnapshotWorker.get_old_events(cutoff)

      assert result == []
    end

    test "filters across batches correctly (mix of old and new events)" do
      cutoff = ~U[2025-06-01 00:00:00Z]

      batch_1 = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.PlayRecorded",
          data: %{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-1"},
          created_at: ~U[2025-05-01 00:00:00Z]
        ),
        # This one is newer than cutoff - should be excluded
        build_recorded_event(
          event_number: 2,
          event_type: "Elixir.BaladosSyncCore.Events.PlayRecorded",
          data: %{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-2"},
          created_at: ~U[2025-07-01 00:00:00Z]
        )
      ]

      batch_2 = [
        build_recorded_event(
          event_number: 3,
          event_type: "Elixir.BaladosSyncCore.Events.UserSubscribed",
          data: %{user_id: "user-2", rss_source_feed: "feed-2"},
          created_at: ~U[2025-04-01 00:00:00Z]
        ),
        # Non-target event type - should be excluded
        build_recorded_event(
          event_number: 4,
          event_type: "Elixir.BaladosSyncCore.Events.PrivacyChanged",
          data: %{user_id: "user-2"},
          created_at: ~U[2025-03-01 00:00:00Z]
        )
      ]

      mock_module = define_mock_event_store([batch_1, batch_2])
      Application.put_env(:balados_sync_jobs, :event_store, mock_module)

      result = SnapshotWorker.get_old_events(cutoff)

      assert length(result) == 2
      assert Enum.at(result, 0).item == "item-1"
      assert Enum.at(result, 1).feed == "feed-2"
    end

    test "error mid-pagination returns error (no partial results)" do
      batch_1 = [
        build_recorded_event(
          event_number: 1,
          event_type: "Elixir.BaladosSyncCore.Events.PlayRecorded",
          data: %{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-1"},
          created_at: ~U[2025-01-01 00:00:00Z]
        )
      ]

      mock_module = define_mock_event_store([batch_1, :error])
      Application.put_env(:balados_sync_jobs, :event_store, mock_module)

      cutoff = ~U[2025-06-01 00:00:00Z]

      # Error mid-pagination: get_old_events returns [] (graceful degradation)
      result = SnapshotWorker.get_old_events(cutoff)

      assert result == []
    end
  end

  # Creates a mock EventStore module that returns pre-defined batches.
  # Each call to read_all_streams_forward returns the next batch in sequence.
  # Pass :error to simulate an EventStore failure.
  # Pass a list of batches (each batch is a list of events) for pagination.
  defp define_mock_event_store(:error) do
    {:ok, agent} = Agent.start_link(fn -> :error end)
    create_mock_module(agent)
  end

  defp define_mock_event_store(batches) when is_list(batches) do
    {:ok, agent} = Agent.start_link(fn -> batches end)
    create_mock_module(agent)
  end

  defp create_mock_module(agent) do
    # Generate a unique module name to avoid conflicts between tests
    module_name = :"MockEventStore_#{System.unique_integer([:positive])}"

    Module.create(
      module_name,
      quote do
        def read_all_streams_forward(_start_from, _batch_size) do
          Agent.get_and_update(unquote(agent), fn
            :error ->
              {{:error, :connection_timeout}, :error}

            [] ->
              {{:ok, []}, []}

            [batch | rest] when batch == :error ->
              {{:error, :connection_timeout}, rest}

            [batch | rest] ->
              {{:ok, batch}, rest}
          end)
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module_name
  end

  # Helper to build RecordedEvent structs for testing
  defp build_recorded_event(opts) do
    %RecordedEvent{
      event_number: Keyword.fetch!(opts, :event_number),
      event_id: Ecto.UUID.generate(),
      stream_uuid: Keyword.get(opts, :stream_uuid, "user-test"),
      stream_version: Keyword.get(opts, :stream_version, 1),
      correlation_id: nil,
      causation_id: nil,
      event_type: Keyword.fetch!(opts, :event_type),
      data: Keyword.fetch!(opts, :data),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: Keyword.fetch!(opts, :created_at)
    }
  end
end
