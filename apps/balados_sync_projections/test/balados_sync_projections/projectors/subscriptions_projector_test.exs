defmodule BaladosSyncProjections.Projectors.SubscriptionsProjectorTest do
  @moduledoc """
  Tests for SubscriptionsProjector logic.

  These tests verify that subscription events are correctly projected to the
  database. Uses ProjectorTestCase to simulate projector behavior without
  running the actual Commanded GenServer processes.
  """

  use BaladosSyncProjections.ProjectorTestCase

  describe "UserSubscribed projection" do
    test "creates subscription from event" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      subscribed_at = now()

      event = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: subscribed_at
      }

      assert {:ok, _} = apply_event(event)

      subscription = ProjectionsRepo.get_by(Subscription, user_id: user_id, rss_source_feed: feed)

      assert subscription != nil
      assert subscription.user_id == user_id
      assert subscription.rss_source_feed == feed
      assert subscription.rss_source_id == "podcast-123"
      assert subscription.subscribed_at == subscribed_at
      assert subscription.unsubscribed_at == nil
    end

    test "creates multiple subscriptions for same user" do
      user_id = uuid()
      feed1 = encode_feed("https://podcast1.example.com/feed.xml")
      feed2 = encode_feed("https://podcast2.example.com/feed.xml")
      subscribed_at = now()

      event1 = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed1,
        rss_source_id: "podcast-1",
        subscribed_at: subscribed_at
      }

      event2 = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed2,
        rss_source_id: "podcast-2",
        subscribed_at: subscribed_at
      }

      assert {:ok, _} = apply_event(event1)
      assert {:ok, _} = apply_event(event2)

      subscriptions =
        from(s in Subscription, where: s.user_id == ^user_id)
        |> ProjectionsRepo.all()

      assert length(subscriptions) == 2
      assert Enum.any?(subscriptions, &(&1.rss_source_feed == feed1))
      assert Enum.any?(subscriptions, &(&1.rss_source_feed == feed2))
    end

    test "isolates subscriptions between users" do
      user1 = uuid()
      user2 = uuid()
      feed = encode_feed("https://same-podcast.example.com/feed.xml")

      event1 = %UserSubscribed{
        user_id: user1,
        rss_source_feed: feed,
        rss_source_id: "podcast",
        subscribed_at: now()
      }

      event2 = %UserSubscribed{
        user_id: user2,
        rss_source_feed: feed,
        rss_source_id: "podcast",
        subscribed_at: now()
      }

      assert {:ok, _} = apply_event(event1)
      assert {:ok, _} = apply_event(event2)

      sub1 = ProjectionsRepo.get_by(Subscription, user_id: user1, rss_source_feed: feed)
      sub2 = ProjectionsRepo.get_by(Subscription, user_id: user2, rss_source_feed: feed)

      assert sub1 != nil
      assert sub2 != nil
      assert sub1.id != sub2.id
    end

    test "is idempotent on replay" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      subscribed_at = now()

      event = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: subscribed_at
      }

      # Apply same event multiple times
      assert {:ok, _} = apply_event(event)
      assert {:ok, _} = apply_event(event)
      assert {:ok, _} = apply_event(event)

      # Should only have one record
      subscriptions =
        from(s in Subscription, where: s.user_id == ^user_id and s.rss_source_feed == ^feed)
        |> ProjectionsRepo.all()

      assert length(subscriptions) == 1
    end

    test "updates existing subscription on re-subscribe" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      first_sub = now()
      second_sub = DateTime.add(first_sub, 3600, :second)

      # First subscription
      event1 = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-v1",
        subscribed_at: first_sub
      }

      assert {:ok, _} = apply_event(event1)

      # Re-subscribe later with updated rss_source_id
      event2 = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-v2",
        subscribed_at: second_sub
      }

      assert {:ok, _} = apply_event(event2)

      subscription = ProjectionsRepo.get_by(Subscription, user_id: user_id, rss_source_feed: feed)

      assert subscription.rss_source_id == "podcast-v2"
      assert subscription.subscribed_at == second_sub
      assert subscription.unsubscribed_at == nil
    end
  end

  describe "UserUnsubscribed projection" do
    test "marks subscription as unsubscribed" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      subscribed_at = now()
      unsubscribed_at = DateTime.add(subscribed_at, 86400, :second)

      # First subscribe
      subscribe_event = %UserSubscribed{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast",
        subscribed_at: subscribed_at
      }

      assert {:ok, _} = apply_event(subscribe_event)

      # Then unsubscribe
      unsubscribe_event = %UserUnsubscribed{
        user_id: user_id,
        rss_source_feed: feed,
        unsubscribed_at: unsubscribed_at
      }

      assert {:ok, _} = apply_event(unsubscribe_event)

      subscription = ProjectionsRepo.get_by(Subscription, user_id: user_id, rss_source_feed: feed)

      assert subscription.unsubscribed_at != nil
    end

    test "does not affect other users' subscriptions" do
      user1 = uuid()
      user2 = uuid()
      feed = encode_feed("https://example.com/podcast.xml")

      # Both users subscribe
      for user <- [user1, user2] do
        assert {:ok, _} =
                 apply_event(%UserSubscribed{
                   user_id: user,
                   rss_source_feed: feed,
                   rss_source_id: "podcast",
                   subscribed_at: now()
                 })
      end

      # Only user1 unsubscribes
      assert {:ok, _} =
               apply_event(%UserUnsubscribed{
                 user_id: user1,
                 rss_source_feed: feed,
                 unsubscribed_at: now()
               })

      sub1 = ProjectionsRepo.get_by(Subscription, user_id: user1, rss_source_feed: feed)
      sub2 = ProjectionsRepo.get_by(Subscription, user_id: user2, rss_source_feed: feed)

      assert sub1.unsubscribed_at != nil
      assert sub2.unsubscribed_at == nil
    end
  end
end
