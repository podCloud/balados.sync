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

  # LikePodcast - idempotent: no-op if already liked
  def execute(%__MODULE__{} = state, %LikePodcast{} = cmd) do
    case get_in_map(state.podcast_likes, cmd.rss_source_feed) do
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
    case get_in_map(state.podcast_likes, cmd.rss_source_feed) do
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
    case get_in_map(state.episode_likes, cmd.rss_source_item) do
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
    case get_in_map(state.episode_likes, cmd.rss_source_item) do
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
      podcast_likes: state.podcast_likes || %{},
      episode_likes: state.episode_likes || %{},
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # Apply events

  def apply(%__MODULE__{} = state, %PodcastLiked{} = event) do
    likes = state.podcast_likes || %{}

    updated = %{
      liked_at: event.liked_at,
      unliked_at: nil
    }

    %{
      state
      | user_id: event.user_id,
        podcast_likes: Map.put(likes, event.rss_source_feed, updated)
    }
  end

  def apply(%__MODULE__{} = state, %PodcastUnliked{} = event) do
    likes = state.podcast_likes || %{}

    case Map.get(likes, event.rss_source_feed) do
      nil ->
        state

      like ->
        updated = Map.put(like, :unliked_at, event.unliked_at)
        %{state | podcast_likes: Map.put(likes, event.rss_source_feed, updated)}
    end
  end

  def apply(%__MODULE__{} = state, %EpisodeLiked{} = event) do
    likes = state.episode_likes || %{}

    updated = %{
      liked_at: event.liked_at,
      unliked_at: nil,
      rss_source_feed: event.rss_source_feed
    }

    %{
      state
      | user_id: event.user_id,
        episode_likes: Map.put(likes, event.rss_source_item, updated)
    }
  end

  def apply(%__MODULE__{} = state, %EpisodeUnliked{} = event) do
    likes = state.episode_likes || %{}

    case Map.get(likes, event.rss_source_item) do
      nil ->
        state

      like ->
        updated = Map.put(like, :unliked_at, event.unliked_at)
        %{state | episode_likes: Map.put(likes, event.rss_source_item, updated)}
    end
  end

  def apply(%__MODULE__{} = state, %LikeCheckpoint{} = event) do
    %{
      state
      | user_id: event.user_id,
        podcast_likes: event.podcast_likes || %{},
        episode_likes: event.episode_likes || %{}
    }
  end

  def apply(%__MODULE__{} = state, _event), do: state

  defp get_in_map(nil, _key), do: nil
  defp get_in_map(map, key), do: Map.get(map, key)
end
