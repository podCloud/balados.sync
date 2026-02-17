defmodule BaladosSyncCore.Aggregates.PlayTrackingTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Aggregates.PlayTracking
  alias BaladosSyncCore.Commands.{RecordPlay, UpdatePosition}
  alias BaladosSyncCore.Events.{PlayRecorded, PositionUpdated}

  describe "RecordPlay command" do
    test "records play on new aggregate" do
      state = %PlayTracking{user_id: nil}

      cmd = %RecordPlay{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 120,
        played: false,
        event_infos: %{}
      }

      event = PlayTracking.execute(state, cmd)

      assert %PlayRecorded{} = event
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
      assert event.rss_source_item == "item-1"
      assert event.position == 120
      assert event.played == false
    end

    test "records play on existing aggregate" do
      state = %PlayTracking{user_id: "user-1", play_statuses: %{}}

      cmd = %RecordPlay{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 300,
        played: true,
        event_infos: %{}
      }

      event = PlayTracking.execute(state, cmd)

      assert %PlayRecorded{} = event
      assert event.played == true
      assert event.position == 300
    end
  end

  describe "UpdatePosition command" do
    test "updates position on new aggregate" do
      state = %PlayTracking{user_id: nil}

      cmd = %UpdatePosition{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 60,
        event_infos: %{}
      }

      event = PlayTracking.execute(state, cmd)

      assert %PositionUpdated{} = event
      assert event.user_id == "user-1"
      assert event.position == 60
    end

    test "updates position on existing aggregate" do
      state = %PlayTracking{user_id: "user-1", play_statuses: %{}}

      cmd = %UpdatePosition{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 180,
        event_infos: %{}
      }

      event = PlayTracking.execute(state, cmd)

      assert %PositionUpdated{} = event
      assert event.position == 180
    end
  end

  describe "Event Application (apply/2)" do
    test "apply PlayRecorded sets play status" do
      state = %PlayTracking{user_id: "user-1", play_statuses: %{}}
      now = DateTime.utc_now()

      event = %PlayRecorded{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 120,
        played: false,
        timestamp: now,
        event_infos: %{}
      }

      updated = PlayTracking.apply(state, event)

      assert Map.has_key?(updated.play_statuses, "item-1")
      status = updated.play_statuses["item-1"]
      assert status.position == 120
      assert status.played == false
      assert status.rss_source_feed == "feed-1"
      assert status.updated_at == now
    end

    test "apply PlayRecorded sets user_id on new aggregate" do
      state = %PlayTracking{user_id: nil, play_statuses: nil}

      event = %PlayRecorded{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 0,
        played: false,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = PlayTracking.apply(state, event)

      assert updated.user_id == "user-1"
    end

    test "apply PositionUpdated updates existing status" do
      now = DateTime.utc_now()

      state = %PlayTracking{
        user_id: "user-1",
        play_statuses: %{
          "item-1" => %{
            position: 60,
            played: false,
            updated_at: now,
            rss_source_feed: "feed-1"
          }
        }
      }

      later = DateTime.add(now, 60, :second)

      event = %PositionUpdated{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        position: 180,
        timestamp: later,
        event_infos: %{}
      }

      updated = PlayTracking.apply(state, event)

      status = updated.play_statuses["item-1"]
      assert status.position == 180
      assert status.updated_at == later
      # played should be preserved from existing
      assert status.played == false
    end

    test "apply PositionUpdated creates new status if not existing" do
      state = %PlayTracking{user_id: "user-1", play_statuses: %{}}

      event = %PositionUpdated{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-new",
        position: 45,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = PlayTracking.apply(state, event)

      assert Map.has_key?(updated.play_statuses, "item-new")
      assert updated.play_statuses["item-new"].position == 45
    end
  end
end
