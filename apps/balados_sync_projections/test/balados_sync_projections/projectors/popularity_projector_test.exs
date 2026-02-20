defmodule BaladosSyncProjections.Projectors.PopularityProjectorTest do
  @moduledoc """
  Tests for PopularityProjector like/unlike event handlers.

  Uses ProjectorTestCase to apply events directly to the database,
  verifying popularity projections are updated correctly.
  """

  use BaladosSyncProjections.ProjectorTestCase

  describe "PodcastLiked" do
    test "creates podcast popularity record on first like" do
      feed = encode_feed("https://example.com/feed.xml")
      user_id = uuid()

      event = %PodcastLiked{
        user_id: user_id,
        rss_source_feed: feed,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, pop} = apply_popularity_event(event)
      assert pop.likes == 1
      assert pop.score == 7
      assert pop.likes_people == [user_id]
    end

    test "increments likes for existing popularity record" do
      feed = encode_feed("https://example.com/feed.xml")

      # First like
      event1 = %PodcastLiked{
        user_id: uuid(),
        rss_source_feed: feed,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_popularity_event(event1)

      # Second like from different user
      user2 = uuid()

      event2 = %PodcastLiked{
        user_id: user2,
        rss_source_feed: feed,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, pop} = apply_popularity_event(event2)
      assert pop.likes == 2
      assert pop.score == 14
      assert user2 in pop.likes_people
    end
  end

  describe "PodcastUnliked" do
    test "decrements likes and removes user from likes_people" do
      feed = encode_feed("https://example.com/feed.xml")
      user_id = uuid()

      # Like first
      like_event = %PodcastLiked{
        user_id: user_id,
        rss_source_feed: feed,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_popularity_event(like_event)

      # Unlike
      unlike_event = %PodcastUnliked{
        user_id: user_id,
        rss_source_feed: feed,
        unliked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, pop} = apply_popularity_event(unlike_event)
      assert pop.likes == 0
      assert pop.score == 0
      refute user_id in pop.likes_people
    end

    test "no-op when no popularity record exists" do
      event = %PodcastUnliked{
        user_id: uuid(),
        rss_source_feed: encode_feed("https://nonexistent.com/feed.xml"),
        unliked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, nil} = apply_popularity_event(event)
    end

    test "score never goes below zero" do
      feed = encode_feed("https://example.com/feed.xml")
      user_id = uuid()

      # Like then unlike twice (simulate edge case)
      like_event = %PodcastLiked{
        user_id: user_id,
        rss_source_feed: feed,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_popularity_event(like_event)

      unlike_event = %PodcastUnliked{
        user_id: user_id,
        rss_source_feed: feed,
        unliked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, pop1} = apply_popularity_event(unlike_event)
      assert pop1.score == 0
      assert pop1.likes == 0

      # Unlike again — score should stay at 0
      assert {:ok, pop2} = apply_popularity_event(unlike_event)
      assert pop2.score == 0
      assert pop2.likes == 0
    end
  end

  describe "EpisodeLiked" do
    test "creates episode popularity and increments podcast score" do
      feed = encode_feed("https://example.com/feed.xml")
      item = encode_item("episode-1", "https://example.com/ep1.mp3")
      user_id = uuid()

      event = %EpisodeLiked{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_popularity_event(event)

      # Check episode popularity
      episode_pop = ProjectionsRepo.get(EpisodePopularity, item)
      assert episode_pop.likes == 1
      assert episode_pop.score == 7
      assert user_id in episode_pop.likes_people

      # Check podcast score was also incremented
      podcast_pop = ProjectionsRepo.get(PodcastPopularity, feed)
      assert podcast_pop.score == 7
    end
  end

  describe "EpisodeUnliked" do
    test "decrements episode popularity and podcast score" do
      feed = encode_feed("https://example.com/feed.xml")
      item = encode_item("episode-1", "https://example.com/ep1.mp3")
      user_id = uuid()

      # Like first
      like_event = %EpisodeLiked{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        liked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_popularity_event(like_event)

      # Unlike
      unlike_event = %EpisodeUnliked{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        unliked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_popularity_event(unlike_event)

      # Check episode popularity
      episode_pop = ProjectionsRepo.get(EpisodePopularity, item)
      assert episode_pop.likes == 0
      assert episode_pop.score == 0
      refute user_id in episode_pop.likes_people

      # Check podcast score was also decremented
      podcast_pop = ProjectionsRepo.get(PodcastPopularity, feed)
      assert podcast_pop.score == 0
    end

    test "no-op when no episode popularity record exists" do
      event = %EpisodeUnliked{
        user_id: uuid(),
        rss_source_feed: encode_feed("https://example.com/feed.xml"),
        rss_source_item: encode_item("nonexistent", "https://example.com/nope.mp3"),
        unliked_at: now(),
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, nil} = apply_popularity_event(event)
    end
  end
end
