defmodule BaladosSyncCore.Aggregates.LikeTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Aggregates.Like

  alias BaladosSyncCore.Commands.{
    LikePodcast,
    UnlikePodcast,
    LikeEpisode,
    UnlikeEpisode,
    SnapshotLike
  }

  alias BaladosSyncCore.Events.{
    PodcastLiked,
    PodcastUnliked,
    EpisodeLiked,
    EpisodeUnliked,
    LikeCheckpoint
  }

  describe "LikePodcast command" do
    test "emits PodcastLiked on new aggregate" do
      state = %Like{user_id: nil}
      cmd = %LikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}

      event = Like.execute(state, cmd)

      assert %PodcastLiked{} = event
      assert event.user_id == "user-1"
      assert event.rss_source_feed == "feed-1"
      assert event.liked_at != nil
    end

    test "is idempotent - returns empty list if already liked" do
      state = %Like{
        user_id: "user-1",
        podcast_likes: %{"feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z], unliked_at: nil}}
      }

      cmd = %LikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}

      assert [] = Like.execute(state, cmd)
    end

    test "emits PodcastLiked if previously unliked (re-like)" do
      state = %Like{
        user_id: "user-1",
        podcast_likes: %{
          "feed-1" => %{
            liked_at: ~U[2024-01-01 00:00:00Z],
            unliked_at: ~U[2024-01-02 00:00:00Z]
          }
        }
      }

      cmd = %LikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}

      event = Like.execute(state, cmd)

      assert %PodcastLiked{} = event
    end

    test "uses provided liked_at timestamp" do
      state = %Like{user_id: nil}
      ts = ~U[2025-06-15 12:00:00Z]
      cmd = %LikePodcast{user_id: "user-1", rss_source_feed: "feed-1", liked_at: ts}

      event = Like.execute(state, cmd)

      assert event.liked_at == ts
    end
  end

  describe "UnlikePodcast command" do
    test "emits PodcastUnliked when currently liked" do
      state = %Like{
        user_id: "user-1",
        podcast_likes: %{"feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z], unliked_at: nil}}
      }

      cmd = %UnlikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}

      event = Like.execute(state, cmd)

      assert %PodcastUnliked{} = event
      assert event.rss_source_feed == "feed-1"
    end

    test "is idempotent - returns empty list if not currently liked" do
      state = %Like{user_id: "user-1", podcast_likes: %{}}
      cmd = %UnlikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}

      assert [] = Like.execute(state, cmd)
    end

    test "is idempotent - returns empty list if already unliked" do
      state = %Like{
        user_id: "user-1",
        podcast_likes: %{
          "feed-1" => %{
            liked_at: ~U[2024-01-01 00:00:00Z],
            unliked_at: ~U[2024-01-02 00:00:00Z]
          }
        }
      }

      cmd = %UnlikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}

      assert [] = Like.execute(state, cmd)
    end
  end

  describe "LikeEpisode command" do
    test "emits EpisodeLiked on new aggregate" do
      state = %Like{user_id: nil}

      cmd = %LikeEpisode{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1"
      }

      event = Like.execute(state, cmd)

      assert %EpisodeLiked{} = event
      assert event.rss_source_item == "item-1"
      assert event.rss_source_feed == "feed-1"
    end

    test "is idempotent - returns empty list if already liked" do
      state = %Like{
        user_id: "user-1",
        episode_likes: %{
          "item-1" => %{
            liked_at: ~U[2024-01-01 00:00:00Z],
            unliked_at: nil,
            rss_source_feed: "feed-1"
          }
        }
      }

      cmd = %LikeEpisode{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1"
      }

      assert [] = Like.execute(state, cmd)
    end
  end

  describe "UnlikeEpisode command" do
    test "emits EpisodeUnliked when currently liked" do
      state = %Like{
        user_id: "user-1",
        episode_likes: %{
          "item-1" => %{
            liked_at: ~U[2024-01-01 00:00:00Z],
            unliked_at: nil,
            rss_source_feed: "feed-1"
          }
        }
      }

      cmd = %UnlikeEpisode{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1"
      }

      event = Like.execute(state, cmd)

      assert %EpisodeUnliked{} = event
      assert event.rss_source_item == "item-1"
    end

    test "is idempotent - returns empty list if not currently liked" do
      state = %Like{user_id: "user-1", episode_likes: %{}}

      cmd = %UnlikeEpisode{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1"
      }

      assert [] = Like.execute(state, cmd)
    end
  end

  describe "SnapshotLike command" do
    test "returns empty list for uninitialized aggregate" do
      state = %Like{user_id: nil}
      cmd = %SnapshotLike{user_id: "user-1"}

      assert [] = Like.execute(state, cmd)
    end

    test "emits LikeCheckpoint with current state" do
      state = %Like{
        user_id: "user-1",
        podcast_likes: %{"feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z], unliked_at: nil}},
        episode_likes: %{
          "item-1" => %{
            liked_at: ~U[2024-01-01 00:00:00Z],
            unliked_at: nil,
            rss_source_feed: "feed-1"
          }
        }
      }

      cmd = %SnapshotLike{user_id: "user-1"}

      event = Like.execute(state, cmd)

      assert %LikeCheckpoint{} = event
      assert event.user_id == "user-1"
      assert map_size(event.podcast_likes) == 1
      assert map_size(event.episode_likes) == 1
    end
  end

  describe "apply events" do
    test "PodcastLiked sets liked state" do
      state = %Like{user_id: nil}

      event = %PodcastLiked{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        liked_at: ~U[2024-01-01 00:00:00Z]
      }

      new_state = Like.apply(state, event)

      assert new_state.user_id == "user-1"
      assert new_state.podcast_likes["feed-1"].liked_at == ~U[2024-01-01 00:00:00Z]
      assert new_state.podcast_likes["feed-1"].unliked_at == nil
    end

    test "PodcastUnliked sets unliked state" do
      state = %Like{
        user_id: "user-1",
        podcast_likes: %{"feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z], unliked_at: nil}}
      }

      event = %PodcastUnliked{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        unliked_at: ~U[2024-01-02 00:00:00Z]
      }

      new_state = Like.apply(state, event)

      assert new_state.podcast_likes["feed-1"].unliked_at == ~U[2024-01-02 00:00:00Z]
    end

    test "EpisodeLiked sets liked state" do
      state = %Like{user_id: nil}

      event = %EpisodeLiked{
        user_id: "user-1",
        rss_source_feed: "feed-1",
        rss_source_item: "item-1",
        liked_at: ~U[2024-01-01 00:00:00Z]
      }

      new_state = Like.apply(state, event)

      assert new_state.episode_likes["item-1"].liked_at == ~U[2024-01-01 00:00:00Z]
      assert new_state.episode_likes["item-1"].rss_source_feed == "feed-1"
    end

    test "LikeCheckpoint restores full state" do
      state = %Like{user_id: nil}

      podcast_likes = %{
        "feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z], unliked_at: nil}
      }

      episode_likes = %{
        "item-1" => %{
          liked_at: ~U[2024-01-01 00:00:00Z],
          unliked_at: nil,
          rss_source_feed: "feed-1"
        }
      }

      event = %LikeCheckpoint{
        user_id: "user-1",
        podcast_likes: podcast_likes,
        episode_likes: episode_likes
      }

      new_state = Like.apply(state, event)

      assert new_state.user_id == "user-1"
      assert new_state.podcast_likes == podcast_likes
      assert new_state.episode_likes == episode_likes
    end

    test "LikeCheckpoint normalizes string keys from JSON deserialization" do
      state = %Like{user_id: nil}

      # Simulate what the event store returns after JSON deserialization:
      # nested map keys become strings instead of atoms
      event = %LikeCheckpoint{
        user_id: "user-1",
        podcast_likes: %{
          "feed-1" => %{"liked_at" => ~U[2024-01-01 00:00:00Z], "unliked_at" => nil}
        },
        episode_likes: %{
          "item-1" => %{
            "liked_at" => ~U[2024-01-01 00:00:00Z],
            "unliked_at" => nil,
            "rss_source_feed" => "feed-1"
          }
        }
      }

      new_state = Like.apply(state, event)

      # After normalization, keys should be atoms
      assert new_state.podcast_likes["feed-1"].liked_at == ~U[2024-01-01 00:00:00Z]
      assert new_state.podcast_likes["feed-1"].unliked_at == nil
      assert new_state.episode_likes["item-1"].liked_at == ~U[2024-01-01 00:00:00Z]
      assert new_state.episode_likes["item-1"].rss_source_feed == "feed-1"

      # Idempotency should work after checkpoint replay with string keys
      cmd = %LikePodcast{user_id: "user-1", rss_source_feed: "feed-1"}
      assert [] = Like.execute(new_state, cmd)
    end

    test "unknown events are ignored" do
      state = %Like{user_id: "user-1", podcast_likes: %{}, episode_likes: %{}}
      new_state = Like.apply(state, %{some: "unknown event"})
      assert new_state == state
    end
  end
end
