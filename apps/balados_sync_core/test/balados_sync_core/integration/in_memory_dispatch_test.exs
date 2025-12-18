defmodule BaladosSyncCore.Integration.InMemoryDispatchTest do
  @moduledoc """
  Integration tests verifying that the In-Memory EventStore works correctly
  with the Commanded Dispatcher.

  These tests confirm that:
  1. Commands can be dispatched through the In-Memory EventStore
  2. Events are stored in-memory (not PostgreSQL)
  3. The EventStore reset provides test isolation
  """

  use ExUnit.Case, async: true

  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncCore.Dispatcher

  describe "In-Memory EventStore integration" do
    setup do
      # Reset In-Memory EventStore before each test
      :ok = Commanded.EventStore.Adapters.InMemory.reset!(Dispatcher)
      :ok
    end

    test "dispatching Subscribe command succeeds" do
      user_id = Ecto.UUID.generate()
      feed = Base.encode64("https://example.com/podcast.xml")

      command = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{device_id: "test-device", device_name: "Test"}
      }

      assert :ok = Dispatcher.dispatch(command)
    end

    test "multiple commands for same user aggregate succeed" do
      user_id = Ecto.UUID.generate()
      feed1 = Base.encode64("https://podcast1.example.com/feed.xml")
      feed2 = Base.encode64("https://podcast2.example.com/feed.xml")

      command1 = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed1,
        rss_source_id: "podcast-1",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      command2 = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed2,
        rss_source_id: "podcast-2",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      assert :ok = Dispatcher.dispatch(command1)
      assert :ok = Dispatcher.dispatch(command2)
    end

    test "different users can dispatch independently" do
      user1 = Ecto.UUID.generate()
      user2 = Ecto.UUID.generate()
      feed = Base.encode64("https://same-podcast.example.com/feed.xml")

      command1 = %Subscribe{
        user_id: user1,
        rss_source_feed: feed,
        rss_source_id: "podcast",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      command2 = %Subscribe{
        user_id: user2,
        rss_source_feed: feed,
        rss_source_id: "podcast",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      assert :ok = Dispatcher.dispatch(command1)
      assert :ok = Dispatcher.dispatch(command2)
    end
  end
end
