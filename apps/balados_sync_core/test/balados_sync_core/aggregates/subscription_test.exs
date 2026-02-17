defmodule BaladosSyncCore.Aggregates.SubscriptionTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Aggregates.Subscription
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncCore.Events.UserSubscribed

  describe "Subscription aggregate" do
    test "handles Subscribe command on new aggregate" do
      state = %Subscription{user_id: nil}

      cmd = %Subscribe{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_id: "source-1"
      }

      event = Subscription.execute(state, cmd)

      assert event.__struct__ == UserSubscribed
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
    end

    test "handles Subscribe command on existing aggregate" do
      state = %Subscription{user_id: "user-1", subscriptions: %{}}

      cmd = %Subscribe{
        user_id: "user-1",
        rss_source_feed: "feed-2",
        rss_source_id: "source-2"
      }

      event = Subscription.execute(state, cmd)

      assert event.__struct__ == UserSubscribed
      assert event.rss_source_feed == "feed-2"
    end

    test "applies UserSubscribed event records subscription" do
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
      sub = updated.subscriptions["feed-1"]
      assert sub.unsubscribed_at == nil
      assert sub.rss_source_id == "source-1"
    end

    test "filter_subscriptions removes old unsubscribed feeds" do
      now = DateTime.utc_now()
      sixty_days_ago = DateTime.add(now, -60, :day)
      ten_days_ago = DateTime.add(now, -10, :day)

      subscriptions = %{
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

      filtered = Subscription.filter_subscriptions(subscriptions)

      assert Map.has_key?(filtered, "active-feed")
      assert Map.has_key?(filtered, "recently-unsubscribed")
      refute Map.has_key?(filtered, "old-unsubscribed")
    end
  end
end
