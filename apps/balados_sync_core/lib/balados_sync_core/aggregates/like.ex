defmodule BaladosSyncCore.Aggregates.Like do
  @moduledoc """
  Like aggregate for the CQRS/Event Sourcing system.

  Handles user likes for podcasts and episodes.

  ## Bounded Context

  This aggregate is part of the like bounded context, separate from
  subscriptions, play tracking, playlists, and collections.

  ## State

  - `user_id` - Unique identifier for the user
  - `podcast_likes` - Map of `%{feed => %{liked_at, unliked_at}}`
  - `episode_likes` - Map of `%{item => %{liked_at, unliked_at, rss_source_feed}}`
  """

  defstruct [
    :user_id,
    # %{rss_source_feed => %{liked_at, unliked_at}}
    podcast_likes: %{},
    # %{rss_source_item => %{liked_at, unliked_at, rss_source_feed}}
    episode_likes: %{}
  ]

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

  alias BaladosSyncCore.LikeNormalizer

  # LikePodcast - idempotent: no-op if already liked
  def execute(%__MODULE__{} = state, %LikePodcast{} = cmd) do
    case Map.get(state.podcast_likes, cmd.rss_source_feed) do
      %{liked_at: liked_at, unliked_at: unliked_at}
      when not is_nil(liked_at) and is_nil(unliked_at) ->
        []

      _ ->
        %PodcastLiked{
          user_id: cmd.user_id,
          rss_source_feed: cmd.rss_source_feed,
          liked_at: cmd.liked_at || DateTime.utc_now() |> DateTime.truncate(:second),
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          event_infos: cmd.event_infos || %{}
        }
    end
  end

  # UnlikePodcast - idempotent: no-op if not currently liked
  def execute(%__MODULE__{} = state, %UnlikePodcast{} = cmd) do
    case Map.get(state.podcast_likes, cmd.rss_source_feed) do
      %{liked_at: liked_at, unliked_at: unliked_at}
      when not is_nil(liked_at) and is_nil(unliked_at) ->
        %PodcastUnliked{
          user_id: cmd.user_id,
          rss_source_feed: cmd.rss_source_feed,
          unliked_at: cmd.unliked_at || DateTime.utc_now() |> DateTime.truncate(:second),
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          event_infos: cmd.event_infos || %{}
        }

      _ ->
        []
    end
  end

  # LikeEpisode - idempotent
  def execute(%__MODULE__{} = state, %LikeEpisode{} = cmd) do
    case Map.get(state.episode_likes, cmd.rss_source_item) do
      %{liked_at: liked_at, unliked_at: unliked_at}
      when not is_nil(liked_at) and is_nil(unliked_at) ->
        []

      _ ->
        %EpisodeLiked{
          user_id: cmd.user_id,
          rss_source_feed: cmd.rss_source_feed,
          rss_source_item: cmd.rss_source_item,
          liked_at: cmd.liked_at || DateTime.utc_now() |> DateTime.truncate(:second),
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          event_infos: cmd.event_infos || %{}
        }
    end
  end

  # UnlikeEpisode - idempotent
  def execute(%__MODULE__{} = state, %UnlikeEpisode{} = cmd) do
    case Map.get(state.episode_likes, cmd.rss_source_item) do
      %{liked_at: liked_at, unliked_at: unliked_at}
      when not is_nil(liked_at) and is_nil(unliked_at) ->
        %EpisodeUnliked{
          user_id: cmd.user_id,
          rss_source_feed: cmd.rss_source_feed,
          rss_source_item: cmd.rss_source_item,
          unliked_at: cmd.unliked_at || DateTime.utc_now() |> DateTime.truncate(:second),
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          event_infos: cmd.event_infos || %{}
        }

      _ ->
        []
    end
  end

  # SnapshotLike — skip if aggregate has never been initialized
  def execute(%__MODULE__{user_id: nil}, %SnapshotLike{}), do: []

  def execute(%__MODULE__{} = state, %SnapshotLike{}) do
    %LikeCheckpoint{
      user_id: state.user_id,
      podcast_likes: filter_old_unlikes(state.podcast_likes),
      episode_likes: filter_old_unlikes(state.episode_likes),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # Apply events

  def apply(%__MODULE__{} = state, %PodcastLiked{} = event) do
    updated = %{
      liked_at: event.liked_at,
      unliked_at: nil
    }

    %{
      state
      | user_id: event.user_id,
        podcast_likes: Map.put(state.podcast_likes, event.rss_source_feed, updated)
    }
  end

  def apply(%__MODULE__{} = state, %PodcastUnliked{} = event) do
    case Map.get(state.podcast_likes, event.rss_source_feed) do
      nil ->
        state

      like ->
        updated = Map.put(like, :unliked_at, event.unliked_at)
        %{state | podcast_likes: Map.put(state.podcast_likes, event.rss_source_feed, updated)}
    end
  end

  def apply(%__MODULE__{} = state, %EpisodeLiked{} = event) do
    updated = %{
      liked_at: event.liked_at,
      unliked_at: nil,
      rss_source_feed: event.rss_source_feed
    }

    %{
      state
      | user_id: event.user_id,
        episode_likes: Map.put(state.episode_likes, event.rss_source_item, updated)
    }
  end

  def apply(%__MODULE__{} = state, %EpisodeUnliked{} = event) do
    case Map.get(state.episode_likes, event.rss_source_item) do
      nil ->
        state

      like ->
        updated = Map.put(like, :unliked_at, event.unliked_at)
        %{state | episode_likes: Map.put(state.episode_likes, event.rss_source_item, updated)}
    end
  end

  def apply(%__MODULE__{} = state, %LikeCheckpoint{} = event) do
    # Normalize keys: after JSON deserialization, nested map keys may be strings
    %{
      state
      | user_id: event.user_id,
        podcast_likes: LikeNormalizer.normalize(event.podcast_likes || %{}),
        episode_likes: LikeNormalizer.normalize(event.episode_likes || %{})
    }
  end

  def apply(%__MODULE__{} = state, _event), do: state

  # Filters out likes that were unliked more than 45 days ago.
  # Active likes and recent unlikes are preserved for idempotence.
  # Matches the subscription aggregate pruning pattern.
  #
  # The unliked_at > liked_at guard (condition 2) prevents pruning entries with
  # corrupted timestamps (e.g. unliked before liked). When liked_at is nil,
  # falls back to epoch so any valid unliked_at passes the guard.
  defp filter_old_unlikes(likes) do
    forty_five_days_ago = DateTime.add(DateTime.utc_now(), -45, :day)

    likes
    |> Enum.reject(fn {_key, like} ->
      like[:unliked_at] != nil &&
        DateTime.compare(like[:unliked_at], like[:liked_at] || DateTime.from_unix!(0)) == :gt &&
        DateTime.compare(like[:unliked_at], forty_five_days_ago) == :lt
    end)
    |> Enum.into(%{})
  end
end
