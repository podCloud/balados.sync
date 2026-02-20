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

  alias BaladosSyncCore.LikeNormalizer
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
      {_count, _} =
        from(ul in UserLike, where: ul.user_id == ^event.user_id)
        |> repo.delete_all()

      # Normalize keys: after JSON deserialization, nested map keys may be strings
      podcast_likes = LikeNormalizer.normalize(event.podcast_likes)
      episode_likes = LikeNormalizer.normalize(event.episode_likes)

      # Build all entries for bulk insert (no N+1 queries since we deleted everything above)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      podcast_entries =
        Enum.map(podcast_likes, fn {feed, like_data} ->
          %{
            user_id: event.user_id,
            rss_source_feed: feed,
            rss_source_item: nil,
            liked_at: like_data.liked_at,
            unliked_at: like_data[:unliked_at],
            inserted_at: now,
            updated_at: now
          }
        end)

      episode_entries =
        Enum.map(episode_likes, fn {item, like_data} ->
          %{
            user_id: event.user_id,
            rss_source_feed: like_data.rss_source_feed,
            rss_source_item: item,
            liked_at: like_data.liked_at,
            unliked_at: like_data[:unliked_at],
            inserted_at: now,
            updated_at: now
          }
        end)

      entries = podcast_entries ++ episode_entries

      if entries != [] do
        {count, _} = repo.insert_all(UserLike, entries)

        Logger.debug(
          "[LikeProjector] Checkpoint applied: #{count} likes for user=#{event.user_id}"
        )
      else
        Logger.debug("[LikeProjector] Checkpoint applied: 0 likes for user=#{event.user_id}")
      end

      {:ok, :checkpoint_applied}
    end)
  end)

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
end
