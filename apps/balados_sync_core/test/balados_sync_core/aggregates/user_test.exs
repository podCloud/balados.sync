defmodule BaladosSyncCore.Aggregates.UserTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Aggregates.User
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncCore.Events.UserSubscribed

  describe "User aggregate" do
    test "handles Subscribe command" do
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

    test "applies UserSubscribed event to create default collection on first subscription" do
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

      # Verify subscription is recorded
      assert updated_user.user_id == "user-1"
      assert Map.has_key?(updated_user.subscriptions, "feed-1")

      # Verify default collection is created
      assert updated_user.collections != nil

      default_collection =
        Enum.find(updated_user.collections, fn {_id, col} -> col.is_default == true end)

      assert default_collection != nil

      {_col_id, default_col} = default_collection
      assert default_col.title == "All Subscriptions"
      assert default_col.is_default == true
      assert MapSet.member?(default_col.feed_ids, "feed-1")
    end
  end
end
