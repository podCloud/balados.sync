defmodule BaladosSyncCore.Aggregates.SubscriptionTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Aggregates.Subscription

  alias BaladosSyncCore.Commands.{
    Subscribe,
    Unsubscribe,
    ShareEpisode,
    ChangePrivacy,
    RemoveEvents,
    SnapshotSubscription
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved,
    SubscriptionCheckpoint
  }

  describe "Subscribe command" do
    test "emits UserSubscribed on new aggregate" do
      state = %Subscription{user_id: nil}
      cmd = %Subscribe{user_id: "user-1", rss_source_feed: "feed-1", rss_source_id: "src-1"}

      event = Subscription.execute(state, cmd)

      assert %UserSubscribed{} = event
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
    end

    test "emits UserSubscribed on existing aggregate" do
      state = %Subscription{user_id: "user-1", subscriptions: %{}}
      cmd = %Subscribe{user_id: "user-1", rss_source_feed: "feed-2", rss_source_id: "src-2"}

      event = Subscription.execute(state, cmd)

      assert %UserSubscribed{} = event
      assert event.rss_source_feed == "feed-2"
    end
  end

  describe "Unsubscribe command" do
    test "emits UserUnsubscribed" do
      state = %Subscription{user_id: "user-1", subscriptions: %{"feed-1" => %{subscribed_at: DateTime.utc_now()}}}
      cmd = %Unsubscribe{user_id: "user-1", rss_source_feed: "feed-1", rss_source_id: "src-1"}

      event = Subscription.execute(state, cmd)

      assert %UserUnsubscribed{} = event
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
    end
  end

  describe "ShareEpisode command" do
    test "emits EpisodeShared" do
      state = %Subscription{user_id: "user-1"}
      cmd = %ShareEpisode{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-1"}

      event = Subscription.execute(state, cmd)

      assert %EpisodeShared{} = event
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
      assert event.rss_source_item == "item-1"
    end
  end

  describe "ChangePrivacy command" do
    test "emits PrivacyChanged" do
      state = %Subscription{user_id: "user-1", privacy: :public}
      cmd = %ChangePrivacy{user_id: "user-1", privacy: :private}

      event = Subscription.execute(state, cmd)

      assert %PrivacyChanged{} = event
      assert event.privacy == :private
    end
  end

  describe "RemoveEvents command" do
    test "emits EventsRemoved" do
      state = %Subscription{user_id: "user-1"}
      cmd = %RemoveEvents{user_id: "user-1", rss_source_feed: "feed-1", rss_source_item: "item-1"}

      event = Subscription.execute(state, cmd)

      assert %EventsRemoved{} = event
      assert event.user_id == "user-1"
    end
  end

  describe "apply events" do
    test "UserSubscribed records subscription" do
      state = %Subscription{user_id: nil}

      event = %UserSubscribed{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_id: "source-1",
        subscribed_at: DateTime.utc_now(),
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Subscription.apply(state, event)

      assert updated.user_id == "user-1"
      assert Map.has_key?(updated.subscriptions, "feed-1")
      assert updated.subscriptions["feed-1"].unsubscribed_at == nil
      assert updated.subscriptions["feed-1"].rss_source_id == "source-1"
    end

    test "UserUnsubscribed marks subscription as unsubscribed" do
      now = DateTime.utc_now()

      state = %Subscription{
        user_id: "user-1",
        subscriptions: %{
          "feed-1" => %{subscribed_at: now, unsubscribed_at: nil, rss_source_id: "src-1"}
        }
      }

      event = %UserUnsubscribed{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        unsubscribed_at: now,
        timestamp: now,
        event_infos: %{}
      }

      updated = Subscription.apply(state, event)

      assert updated.subscriptions["feed-1"].unsubscribed_at == now
    end

    test "UserUnsubscribed ignores unknown feed" do
      state = %Subscription{user_id: "user-1", subscriptions: %{}}

      event = %UserUnsubscribed{
        user_id: "user-1",
        rss_source_feed: "unknown",
        unsubscribed_at: DateTime.utc_now(),
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Subscription.apply(state, event)
      assert updated == state
    end

    test "PrivacyChanged updates privacy" do
      state = %Subscription{user_id: "user-1", privacy: :public}

      event = %PrivacyChanged{
        user_id: "user-1",
        privacy: :private,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Subscription.apply(state, event)
      assert updated.privacy == :private
    end

    test "SubscriptionCheckpoint restores full state including user_id" do
      state = %Subscription{user_id: nil, subscriptions: nil, privacy: nil}

      subs = %{"feed-1" => %{subscribed_at: DateTime.utc_now(), unsubscribed_at: nil}}

      event = %SubscriptionCheckpoint{
        user_id: "user-1",
        subscriptions: subs,
        privacy: :anonymous,
        timestamp: DateTime.utc_now()
      }

      updated = Subscription.apply(state, event)

      assert updated.user_id == "user-1"
      assert updated.subscriptions == subs
      assert updated.privacy == :anonymous
    end
  end

  describe "SnapshotSubscription command" do
    test "emits SubscriptionCheckpoint with current state" do
      state = %Subscription{
        user_id: "user-1",
        privacy: :public,
        subscriptions: %{
          "feed-1" => %{subscribed_at: DateTime.utc_now(), unsubscribed_at: nil}
        }
      }

      event = Subscription.execute(state, %SnapshotSubscription{user_id: "user-1"})

      assert %SubscriptionCheckpoint{} = event
      assert event.user_id == "user-1"
      assert event.privacy == :public
      assert Map.has_key?(event.subscriptions, "feed-1")
    end

    test "filters out old unsubscribed feeds" do
      now = DateTime.utc_now()
      sixty_days_ago = DateTime.add(now, -60, :day)
      ten_days_ago = DateTime.add(now, -10, :day)

      state = %Subscription{
        user_id: "user-1",
        privacy: :public,
        subscriptions: %{
          "active-feed" => %{
            subscribed_at: sixty_days_ago,
            unsubscribed_at: nil
          },
          "recently-unsubscribed" => %{
            subscribed_at: sixty_days_ago,
            unsubscribed_at: ten_days_ago
          },
          "old-unsubscribed" => %{
            subscribed_at: DateTime.add(now, -90, :day),
            unsubscribed_at: sixty_days_ago
          }
        }
      }

      event = Subscription.execute(state, %SnapshotSubscription{user_id: "user-1"})

      assert %SubscriptionCheckpoint{} = event
      assert Map.has_key?(event.subscriptions, "active-feed")
      assert Map.has_key?(event.subscriptions, "recently-unsubscribed")
      refute Map.has_key?(event.subscriptions, "old-unsubscribed")
    end

    test "keeps subscription unsubscribed just under 45 days ago (boundary)" do
      now = DateTime.utc_now()
      # 44 days ago — just inside the 45-day retention window
      forty_four_days_ago = DateTime.add(now, -44, :day)
      ninety_days_ago = DateTime.add(now, -90, :day)

      state = %Subscription{
        user_id: "user-1",
        privacy: :public,
        subscriptions: %{
          "boundary-feed" => %{
            subscribed_at: ninety_days_ago,
            unsubscribed_at: forty_four_days_ago
          }
        }
      }

      event = Subscription.execute(state, %SnapshotSubscription{user_id: "user-1"})

      assert %SubscriptionCheckpoint{} = event
      # 44 days < 45 days threshold, so the subscription should be kept
      assert Map.has_key?(event.subscriptions, "boundary-feed")
    end

    test "filters subscription unsubscribed just over 45 days ago (boundary)" do
      now = DateTime.utc_now()
      # 46 days ago — just outside the 45-day retention window
      forty_six_days_ago = DateTime.add(now, -46, :day)
      ninety_days_ago = DateTime.add(now, -90, :day)

      state = %Subscription{
        user_id: "user-1",
        privacy: :public,
        subscriptions: %{
          "old-feed" => %{
            subscribed_at: ninety_days_ago,
            unsubscribed_at: forty_six_days_ago
          }
        }
      }

      event = Subscription.execute(state, %SnapshotSubscription{user_id: "user-1"})

      assert %SubscriptionCheckpoint{} = event
      # 46 days > 45 days threshold, so the subscription should be filtered
      refute Map.has_key?(event.subscriptions, "old-feed")
    end
  end
end
