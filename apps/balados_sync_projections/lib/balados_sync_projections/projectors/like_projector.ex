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
    Ecto.Multi.run(multi, :like_podcast, fn repo, _changes ->
      upsert_like(repo, event.user_id, event.rss_source_feed, nil, event.liked_at)
    end)
  end)

  project(%PodcastUnliked{} = event, _metadata, fn multi ->
    Ecto.Multi.run(multi, :unlike_podcast, fn repo, _changes ->
      unlike(repo, event.user_id, event.rss_source_feed, nil, event.unliked_at)
    end)
  end)

  project(%EpisodeLiked{} = event, _metadata, fn multi ->
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
    Ecto.Multi.run(multi, :unlike_episode, fn repo, _changes ->
      unlike(repo, event.user_id, event.rss_source_feed, event.rss_source_item, event.unliked_at)
    end)
  end)

  project(%LikeCheckpoint{} = event, _metadata, fn multi ->
    Ecto.Multi.run(multi, :checkpoint, fn repo, _changes ->
      # Delete all existing likes for this user
      from(ul in UserLike, where: ul.user_id == ^event.user_id)
      |> repo.delete_all()

      # Re-insert podcast likes
      podcast_likes = event.podcast_likes || %{}

      for {feed, like_data} <- podcast_likes do
        upsert_like(repo, event.user_id, feed, nil, like_data.liked_at)

        if like_data.unliked_at do
          unlike(repo, event.user_id, feed, nil, like_data.unliked_at)
        end
      end

      # Re-insert episode likes
      episode_likes = event.episode_likes || %{}

      for {item, like_data} <- episode_likes do
        upsert_like(repo, event.user_id, like_data.rss_source_feed, item, like_data.liked_at)

        if like_data.unliked_at do
          unlike(repo, event.user_id, like_data.rss_source_feed, item, like_data.unliked_at)
        end
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
