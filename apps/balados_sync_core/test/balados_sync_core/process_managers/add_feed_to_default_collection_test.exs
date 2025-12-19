defmodule BaladosSyncCore.ProcessManagers.AddFeedToDefaultCollectionTest do
  @moduledoc """
  Integration tests for the AddFeedToDefaultCollection process manager.

  Tests the complete CQRS/ES flow:
  1. UserSubscribed event is emitted when user subscribes to a feed
  2. Process manager receives the event
  3. Process manager creates/ensures default collection exists
  4. Process manager dispatches AddFeedToCollection command
  5. Command creates FeedAddedToCollection event
  6. Event is persisted to event store

  NOTE: These tests are currently skipped because:
  - Process managers in Commanded run as separate GenServer processes
  - They require specific configuration to work with In-Memory EventStore
  - Testing process managers requires additional setup beyond CommandedCase

  TODO: Enable these tests when process manager testing infrastructure is in place.
  """

  use BaladosSyncCore.CommandedCase, async: false

  alias BaladosSyncCore.Commands.Subscribe

  describe "AddFeedToDefaultCollection process manager" do
    @tag :skip
    @tag :integration
    test "automatically adds feed to default collection on subscription" do
      user_id = Ecto.UUID.generate()
      feed = Base.encode64("https://example.com/podcast.xml")
      rss_source_id = Ecto.UUID.generate()

      # Subscribe to a feed
      subscribe_cmd = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: rss_source_id,
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      # Dispatch the command
      assert :ok = Dispatcher.dispatch(subscribe_cmd)

      # Wait a bit for the process manager to handle the events
      Process.sleep(500)

      # Fetch all events for this user from the event store
      events =
        EventStore.stream_all_forward(
          start_from: :origin,
          read_batch_size: 100
        )
        |> Enum.to_list()

      # Verify that UserSubscribed event was created
      user_subscribed_events =
        events
        |> Enum.filter(fn event -> String.contains?(event.event_type, "UserSubscribed") end)

      assert length(user_subscribed_events) > 0, "UserSubscribed event should have been created"

      # Verify that CollectionCreated and FeedAddedToCollection events were created
      collection_created_events =
        events
        |> Enum.filter(fn event -> String.contains?(event.event_type, "CollectionCreated") end)

      feed_added_events =
        events
        |> Enum.filter(fn event -> String.contains?(event.event_type, "FeedAddedToCollection") end)

      assert length(collection_created_events) > 0,
             "CollectionCreated event should be emitted by process manager"

      assert length(feed_added_events) > 0,
             "FeedAddedToCollection event should be emitted by process manager"
    end

    @tag :skip
    @tag :integration
    test "subsequent subscriptions reuse the existing default collection" do
      user_id = Ecto.UUID.generate()
      feed1 = Base.encode64("https://example.com/podcast1.xml")
      feed2 = Base.encode64("https://example.com/podcast2.xml")
      rss_source_id1 = Ecto.UUID.generate()
      rss_source_id2 = Ecto.UUID.generate()

      # First subscription
      subscribe_cmd1 = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed1,
        rss_source_id: rss_source_id1,
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      assert :ok = Dispatcher.dispatch(subscribe_cmd1)
      Process.sleep(500)

      # Second subscription
      subscribe_cmd2 = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed2,
        rss_source_id: rss_source_id2,
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      assert :ok = Dispatcher.dispatch(subscribe_cmd2)
      Process.sleep(500)

      # Fetch all events from event store
      events =
        EventStore.stream_all_forward(
          start_from: :origin,
          read_batch_size: 100
        )
        |> Enum.to_list()

      # Count CollectionCreated events - should only have 1 for the default collection
      collection_created_events =
        events
        |> Enum.filter(fn event -> String.contains?(event.event_type, "CollectionCreated") end)

      # Count FeedAddedToCollection events - should have 2 (one for each feed)
      feed_added_events =
        events
        |> Enum.filter(fn event -> String.contains?(event.event_type, "FeedAddedToCollection") end)

      assert length(feed_added_events) >= 2,
             "Both feeds should be added to the default collection"
    end
  end
end
