defmodule BaladosSyncProjections.Projectors.LikeProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "LikeProjector"

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Events.{
    PodcastLiked,
    PodcastUnliked,
    EpisodeLiked,
    EpisodeUnliked,
    LikeCheckpoint
  }

  alias BaladosSyncProjections.Schemas.UserLike

  project(%PodcastLiked{} = event, _metadata, fn multi ->
    Logger.info(
      "[LikeProjector] PodcastLiked: user=#{event.user_id}, feed=#{event.rss_source_feed}"
    )

    Ecto.Multi.run(multi, :like_podcast, fn repo, _changes ->
      upsert_like(repo, event.user_id, event.rss_source_feed, nil, event.liked_at)
    end)
  end)

  project(%PodcastUnliked{} = event, _metadata, fn multi ->
    Logger.info(
      "[LikeProjector] PodcastUnliked: user=#{event.user_id}, feed=#{event.rss_source_feed}"
    )

    Ecto.Multi.run(multi, :unlike_podcast, fn repo, _changes ->
      unlike(repo, event.user_id, event.rss_source_feed, nil, event.unliked_at)
    end)
  end)

  project(%EpisodeLiked{} = event, _metadata, fn multi ->
    Logger.info(
      "[LikeProjector] EpisodeLiked: user=#{event.user_id}, feed=#{event.rss_source_feed}, item=#{event.rss_source_item}"
    )

    Ecto.Multi.run(multi, :like_episode, fn repo, _changes ->
      upsert_like(
        repo,
        event.user_id,
        event.rss_source_feed,
        event.rss_source_item,
        event.liked_at
      )
    end)
  end)

  project(%EpisodeUnliked{} = event, _metadata, fn multi ->
    Logger.info(
      "[LikeProjector] EpisodeUnliked: user=#{event.user_id}, feed=#{event.rss_source_feed}, item=#{event.rss_source_item}"
    )

    Ecto.Multi.run(multi, :unlike_episode, fn repo, _changes ->
      unlike(repo, event.user_id, event.rss_source_feed, event.rss_source_item, event.unliked_at)
    end)
  end)

  project(%LikeCheckpoint{} = event, _metadata, fn multi ->
    Logger.info("[LikeProjector] LikeCheckpoint: user=#{event.user_id}")

    Ecto.Multi.run(multi, :checkpoint, fn repo, _changes ->
      # Delete all existing likes for this user
      from(ul in UserLike, where: ul.user_id == ^event.user_id)
      |> repo.delete_all()

      # Normalize keys: after JSON deserialization, nested map keys may be strings
      podcast_likes = normalize_likes_map(event.podcast_likes || %{})
      episode_likes = normalize_likes_map(event.episode_likes || %{})

      with :ok <- replay_podcast_likes(repo, event.user_id, podcast_likes),
           :ok <- replay_episode_likes(repo, event.user_id, episode_likes) do
        Logger.debug("[LikeProjector] Checkpoint applied successfully for user=#{event.user_id}")
        {:ok, :checkpoint_applied}
      end
    end)
  end)

  defp replay_podcast_likes(repo, user_id, podcast_likes) do
    Enum.reduce_while(podcast_likes, :ok, fn {feed, like_data}, :ok ->
      with {:ok, _} <- upsert_like(repo, user_id, feed, nil, like_data.liked_at),
           {:ok, _} <- maybe_unlike(repo, user_id, feed, nil, like_data.unliked_at) do
        {:cont, :ok}
      else
        {:error, reason} ->
          Logger.error(
            "[LikeProjector] Checkpoint failed for podcast feed=#{feed}: #{inspect(reason)}"
          )

          {:halt, {:error, reason}}
      end
    end)
  end

  defp replay_episode_likes(repo, user_id, episode_likes) do
    Enum.reduce_while(episode_likes, :ok, fn {item, like_data}, :ok ->
      with {:ok, _} <-
             upsert_like(repo, user_id, like_data.rss_source_feed, item, like_data.liked_at),
           {:ok, _} <-
             maybe_unlike(repo, user_id, like_data.rss_source_feed, item, like_data.unliked_at) do
        {:cont, :ok}
      else
        {:error, reason} ->
          Logger.error(
            "[LikeProjector] Checkpoint failed for episode item=#{item}: #{inspect(reason)}"
          )

          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_unlike(_repo, _user_id, _feed, _item, nil), do: {:ok, nil}

  defp maybe_unlike(repo, user_id, feed, item, unliked_at),
    do: unlike(repo, user_id, feed, item, unliked_at)

  defp upsert_like(repo, user_id, feed, item, liked_at) do
    existing = find_like(repo, user_id, feed, item)

    case existing do
      nil ->
        %UserLike{}
        |> UserLike.changeset(%{
          user_id: user_id,
          rss_source_feed: feed,
          rss_source_item: item,
          liked_at: liked_at,
          unliked_at: nil
        })
        |> repo.insert()

      like ->
        like
        |> UserLike.changeset(%{liked_at: liked_at, unliked_at: nil})
        |> repo.update()
    end
  end

  defp unlike(repo, user_id, feed, item, unliked_at) do
    existing = find_like(repo, user_id, feed, item)

    case existing do
      nil ->
        {:ok, nil}

      like ->
        like
        |> UserLike.changeset(%{unliked_at: unliked_at})
        |> repo.update()
    end
  end

  defp find_like(repo, user_id, feed, nil) do
    from(ul in UserLike,
      where: ul.user_id == ^user_id and ul.rss_source_feed == ^feed and is_nil(ul.rss_source_item)
    )
    |> repo.one()
  end

  defp find_like(repo, user_id, feed, item) do
    from(ul in UserLike,
      where:
        ul.user_id == ^user_id and ul.rss_source_feed == ^feed and
          ul.rss_source_item == ^item
    )
    |> repo.one()
  end

  # Normalize nested like data maps to ensure atom keys after JSON deserialization.
  defp normalize_likes_map(likes) when is_map(likes) do
    Map.new(likes, fn {key, value} -> {key, atomize_keys(value)} end)
  end

  defp normalize_likes_map(_), do: %{}

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp atomize_keys(value), do: value
end
