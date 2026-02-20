defmodule BaladosSyncProjections.Projectors.LikeProjectorTest do
  @moduledoc """
  Tests for LikeProjector logic.

  Verifies that like/unlike events are correctly projected to the user_likes table.
  """

  use BaladosSyncProjections.ProjectorTestCase

  import Ecto.Query

  describe "PodcastLiked projection" do
    test "creates like from event" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      liked_at = now()

      event = %PodcastLiked{
        user_id: user_id,
        rss_source_feed: feed,
        liked_at: liked_at,
        timestamp: now(),
        event_infos: %{}
      }

      assert {:ok, _} = apply_event(event)

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_feed: feed)
      assert like != nil
      assert like.liked_at == liked_at
      assert like.unliked_at == nil
      assert like.rss_source_item == nil
    end

    test "re-like after unlike clears unliked_at" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      liked_at = now()
      unliked_at = DateTime.add(liked_at, 3600, :second)
      re_liked_at = DateTime.add(unliked_at, 3600, :second)

      assert {:ok, _} =
               apply_event(%PodcastLiked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 liked_at: liked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      assert {:ok, _} =
               apply_event(%PodcastUnliked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 unliked_at: unliked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      assert {:ok, _} =
               apply_event(%PodcastLiked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 liked_at: re_liked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_feed: feed)
      assert like.liked_at == re_liked_at
      assert like.unliked_at == nil
    end

    test "isolates likes between users" do
      user1 = uuid()
      user2 = uuid()
      feed = encode_feed("https://example.com/podcast.xml")

      for user <- [user1, user2] do
        assert {:ok, _} =
                 apply_event(%PodcastLiked{
                   user_id: user,
                   rss_source_feed: feed,
                   liked_at: now(),
                   timestamp: now(),
                   event_infos: %{}
                 })
      end

      likes = from(ul in UserLike, where: ul.rss_source_feed == ^feed) |> ProjectionsRepo.all()
      assert length(likes) == 2
    end
  end

  describe "PodcastUnliked projection" do
    test "sets unliked_at on existing like" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      liked_at = now()
      unliked_at = DateTime.add(liked_at, 3600, :second)

      assert {:ok, _} =
               apply_event(%PodcastLiked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 liked_at: liked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      assert {:ok, _} =
               apply_event(%PodcastUnliked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 unliked_at: unliked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_feed: feed)
      assert like.unliked_at == unliked_at
    end

    test "no-op when no existing like" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")

      assert {:ok, nil} =
               apply_event(%PodcastUnliked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 unliked_at: now(),
                 timestamp: now(),
                 event_infos: %{}
               })
    end
  end

  describe "EpisodeLiked projection" do
    test "creates episode like" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("guid-123", "https://example.com/ep1.mp3")
      liked_at = now()

      assert {:ok, _} =
               apply_event(%EpisodeLiked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 rss_source_item: item,
                 liked_at: liked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_item: item)
      assert like != nil
      assert like.rss_source_feed == feed
      assert like.liked_at == liked_at
    end
  end

  describe "EpisodeUnliked projection" do
    test "sets unliked_at on episode like" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("guid-123", "https://example.com/ep1.mp3")
      liked_at = now()
      unliked_at = DateTime.add(liked_at, 3600, :second)

      assert {:ok, _} =
               apply_event(%EpisodeLiked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 rss_source_item: item,
                 liked_at: liked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      assert {:ok, _} =
               apply_event(%EpisodeUnliked{
                 user_id: user_id,
                 rss_source_feed: feed,
                 rss_source_item: item,
                 unliked_at: unliked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_item: item)
      assert like.unliked_at == unliked_at
    end
  end

  describe "LikeCheckpoint projection" do
    test "replaces all likes with checkpoint data" do
      user_id = uuid()
      feed1 = encode_feed("https://podcast1.example.com/feed.xml")
      feed2 = encode_feed("https://podcast2.example.com/feed.xml")
      liked_at = now()

      # Create initial likes
      assert {:ok, _} =
               apply_event(%PodcastLiked{
                 user_id: user_id,
                 rss_source_feed: feed1,
                 liked_at: liked_at,
                 timestamp: now(),
                 event_infos: %{}
               })

      # Apply checkpoint with different data
      feed3 = encode_feed("https://podcast3.example.com/feed.xml")

      assert {:ok, _} =
               apply_event(%LikeCheckpoint{
                 user_id: user_id,
                 podcast_likes: %{
                   feed2 => %{liked_at: liked_at, unliked_at: nil},
                   feed3 => %{liked_at: liked_at, unliked_at: nil}
                 },
                 episode_likes: %{},
                 timestamp: now()
               })

      # feed1 should be gone, feed2 and feed3 should exist
      likes = from(ul in UserLike, where: ul.user_id == ^user_id) |> ProjectionsRepo.all()
      assert length(likes) == 2
      feeds = Enum.map(likes, & &1.rss_source_feed) |> Enum.sort()
      assert feeds == Enum.sort([feed2, feed3])
    end

    test "checkpoint with unliked entries preserves unliked_at" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      liked_at = now()
      unliked_at = DateTime.add(liked_at, 3600, :second)

      assert {:ok, _} =
               apply_event(%LikeCheckpoint{
                 user_id: user_id,
                 podcast_likes: %{
                   feed => %{liked_at: liked_at, unliked_at: unliked_at}
                 },
                 episode_likes: %{},
                 timestamp: now()
               })

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_feed: feed)
      assert like.liked_at == liked_at
      assert like.unliked_at == unliked_at
    end

    test "checkpoint with episode likes" do
      user_id = uuid()
      feed = encode_feed("https://example.com/podcast.xml")
      item = encode_item("guid-1", "https://example.com/ep1.mp3")
      liked_at = now()

      assert {:ok, _} =
               apply_event(%LikeCheckpoint{
                 user_id: user_id,
                 podcast_likes: %{},
                 episode_likes: %{
                   item => %{liked_at: liked_at, unliked_at: nil, rss_source_feed: feed}
                 },
                 timestamp: now()
               })

      like = ProjectionsRepo.get_by(UserLike, user_id: user_id, rss_source_item: item)
      assert like != nil
      assert like.rss_source_feed == feed
      assert like.liked_at == liked_at
    end
  end
end
