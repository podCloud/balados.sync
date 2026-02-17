defmodule BaladosSyncCore.Aggregates.UserTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Aggregates.User
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncCore.Events.UserSubscribed

  describe "User aggregate" do
    test "handles Subscribe command on new aggregate" do
      user = %User{user_id: nil}

      cmd = %Subscribe{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_id: "source-1"
      }

      event = User.execute(user, cmd)

      assert event.__struct__ == UserSubscribed
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
    end

    test "handles Subscribe command on existing aggregate" do
      user = %User{user_id: "user-1", subscriptions: %{}}

      cmd = %Subscribe{
        user_id: "user-1",
        rss_source_feed: "feed-2",
        rss_source_id: "source-2"
      }

      event = User.execute(user, cmd)

      assert event.__struct__ == UserSubscribed
      assert event.rss_source_feed == "feed-2"
    end

    test "applies UserSubscribed event records subscription" do
      user = %User{user_id: nil}

      event = %UserSubscribed{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_id: "source-1",
        subscribed_at: DateTime.utc_now(),
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.user_id == "user-1"
      assert Map.has_key?(updated_user.subscriptions, "feed-1")
      sub = updated_user.subscriptions["feed-1"]
      assert sub.unsubscribed_at == nil
      assert sub.rss_source_id == "source-1"
    end
  end
end
