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
