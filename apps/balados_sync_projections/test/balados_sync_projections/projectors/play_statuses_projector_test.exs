defmodule BaladosSyncProjections.Projectors.PlayStatusesProjectorTest do
  @moduledoc """
  Tests for PlayStatusesProjector logic.

  These tests verify that play recording events are correctly projected to the
  database. Uses ProjectorTestCase to simulate projector behavior without
  running the actual Commanded GenServer processes.
  """

  use BaladosSyncProjections.ProjectorTestCase

  describe "PlayRecorded projection" do
    test "creates play status from event" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("episode-guid-123", "https://example.com/episode.mp3")
      timestamp = now()

      event = %PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 1234,
        played: false,
        timestamp: timestamp
      }

      assert {:ok, _} = apply_event(event)

      play_status = ProjectionsRepo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)

      assert play_status != nil
      assert play_status.user_id == user_id
      assert play_status.rss_source_feed == feed
      assert play_status.rss_source_item == item
      assert play_status.position == 1234
      assert play_status.played == false
    end

    test "updates play status on subsequent events" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("episode-guid-456", "https://example.com/episode.mp3")
      timestamp1 = now()

      # First play - partial listen
      event1 = %PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 500,
        played: false,
        timestamp: timestamp1
      }

      assert {:ok, _} = apply_event(event1)

      play_status = ProjectionsRepo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)
      assert play_status.position == 500
      assert play_status.played == false

      # Second play - completed
      timestamp2 = DateTime.add(timestamp1, 1, :second)

      event2 = %PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 3600,
        played: true,
        timestamp: timestamp2
      }

      assert {:ok, _} = apply_event(event2)

      # Refresh
      play_status = ProjectionsRepo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)
      assert play_status.position == 3600
      assert play_status.played == true
    end

    test "tracks multiple episodes for same user" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item1 = encode_item("episode-1", "https://example.com/ep1.mp3")
      item2 = encode_item("episode-2", "https://example.com/ep2.mp3")
      timestamp = now()

      event1 = %PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item1,
        position: 100,
        played: false,
        timestamp: timestamp
      }

      event2 = %PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item2,
        position: 200,
        played: true,
        timestamp: timestamp
      }

      assert {:ok, _} = apply_event(event1)
      assert {:ok, _} = apply_event(event2)

      play_statuses =
        from(p in PlayStatus, where: p.user_id == ^user_id)
        |> ProjectionsRepo.all()

      assert length(play_statuses) == 2

      ps1 = Enum.find(play_statuses, &(&1.rss_source_item == item1))
      ps2 = Enum.find(play_statuses, &(&1.rss_source_item == item2))

      assert ps1.position == 100
      assert ps1.played == false
      assert ps2.position == 200
      assert ps2.played == true
    end

    test "is idempotent on replay" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("episode-guid-789", "https://example.com/episode.mp3")
      timestamp = now()

      event = %PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 1500,
        played: false,
        timestamp: timestamp
      }

      # Apply same event multiple times
      assert {:ok, _} = apply_event(event)
      assert {:ok, _} = apply_event(event)
      assert {:ok, _} = apply_event(event)

      # Should only have one record
      play_statuses =
        from(p in PlayStatus, where: p.user_id == ^user_id and p.rss_source_item == ^item)
        |> ProjectionsRepo.all()

      assert length(play_statuses) == 1
    end

    test "isolates play statuses between users" do
      user1 = uuid()
      user2 = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("same-episode", "https://example.com/episode.mp3")

      # Both users listen to same episode
      for {user, position, played} <- [{user1, 100, false}, {user2, 3600, true}] do
        assert {:ok, _} = apply_event(%PlayRecorded{
          user_id: user,
          rss_source_feed: feed,
          rss_source_item: item,
          position: position,
          played: played,
          timestamp: now()
        })
      end

      ps1 = ProjectionsRepo.get_by(PlayStatus, user_id: user1, rss_source_item: item)
      ps2 = ProjectionsRepo.get_by(PlayStatus, user_id: user2, rss_source_item: item)

      # Each user has independent play state
      assert ps1.position == 100
      assert ps1.played == false
      assert ps2.position == 3600
      assert ps2.played == true
    end
  end

  describe "PositionUpdated projection" do
    test "updates position without changing played status" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("episode-guid", "https://example.com/episode.mp3")
      timestamp = now()

      # First record a play with played: false
      assert {:ok, _} = apply_event(%PlayRecorded{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 100,
        played: false,
        timestamp: timestamp
      })

      # Update position only
      assert {:ok, _} = apply_event(%PositionUpdated{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 500,
        timestamp: DateTime.add(timestamp, 1, :second)
      })

      play_status = ProjectionsRepo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)

      # Position updated but played status preserved
      assert play_status.position == 500
      assert play_status.played == false
    end

    test "creates play status if not exists" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("new-episode", "https://example.com/episode.mp3")

      # PositionUpdated on a new episode (no prior PlayRecorded)
      assert {:ok, _} = apply_event(%PositionUpdated{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 250,
        timestamp: now()
      })

      play_status = ProjectionsRepo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)

      assert play_status != nil
      assert play_status.position == 250
      # played should be nil or default when created via PositionUpdated
    end
  end
end
