defmodule BaladosSyncProjections.Projectors.PopularityProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "PopularityProjector"

  import Ecto.Query

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    PlayRecorded,
    EpisodeSaved,
    EpisodeShared,
    PopularityRecalculated
  }

  alias BaladosSyncProjections.Schemas.{PodcastPopularity, EpisodePopularity, UserPrivacy}

  # Scores par type d'action
  @score_subscribe 10
  @score_play 5
  @score_save 3
  @score_share 2

  defp is_user_public_with_repo?(repo, user_id, feed, item) do
    query =
      from(p in UserPrivacy,
        where: p.user_id == ^user_id,
        where: fragment("(? IS NULL OR ? = ? OR ? IS NULL)", ^item, p.rss_source_item, ^item, p.rss_source_item),
        where: fragment("(? IS NULL OR ? = ? OR ? IS NULL)", ^feed, p.rss_source_feed, ^feed, p.rss_source_feed),
        order_by: [
          desc:
            fragment(
              "CASE WHEN ? IS NOT NULL THEN 3 WHEN ? IS NOT NULL THEN 2 ELSE 1 END",
              p.rss_source_item,
              p.rss_source_feed
            )
        ],
        limit: 1,
        select: p.privacy
      )

    privacy = repo.one(query) || "public"
    privacy == "public"
  end

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    Ecto.Multi.run(multi, :podcast_popularity, fn repo, _changes ->
      is_public = is_user_public_with_repo?(repo, event.user_id, event.rss_source_feed, nil)

      popularity =
        repo.get(PodcastPopularity, event.rss_source_feed) ||
          %PodcastPopularity{rss_source_feed: event.rss_source_feed}

      updated = %{
        popularity
        | score: popularity.score + @score_subscribe,
          plays_people:
            if(is_public,
              do: add_recent_user(popularity.plays_people, event.user_id),
              else: popularity.plays_people
            )
      }

      repo.insert_or_update(
        PodcastPopularity.changeset(updated, %{}),
        on_conflict: :replace_all,
        conflict_target: :rss_source_feed
      )
    end)
  end)

  project(%UserUnsubscribed{} = _event, _metadata, fn multi ->
    # On pourrait décrémenter le score, mais on choisit de ne pas le faire
    # pour garder une trace de l'engagement historique
    multi
  end)

  project(%PlayRecorded{} = event, _metadata, fn multi ->
    # Incrémenter podcast popularity
    multi =
      Ecto.Multi.run(multi, :podcast_popularity, fn repo, _changes ->
        is_public = is_user_public_with_repo?(repo, event.user_id, event.rss_source_feed, event.rss_source_item)

        popularity =
          repo.get(PodcastPopularity, event.rss_source_feed) ||
            %PodcastPopularity{rss_source_feed: event.rss_source_feed}

        updated = %{
          popularity
          | score: popularity.score + @score_play,
            plays: popularity.plays + 1,
            plays_people:
              if(is_public,
                do: add_recent_user(popularity.plays_people, event.user_id),
                else: popularity.plays_people
              )
        }

        repo.insert_or_update(
          PodcastPopularity.changeset(updated, %{}),
          on_conflict: :replace_all,
          conflict_target: :rss_source_feed
        )
      end)

    # Incrémenter episode popularity
    Ecto.Multi.run(multi, :episode_popularity, fn repo, _changes ->
      is_public = is_user_public_with_repo?(repo, event.user_id, event.rss_source_feed, event.rss_source_item)

      popularity =
        repo.get(EpisodePopularity, event.rss_source_item) ||
          %EpisodePopularity{
            rss_source_item: event.rss_source_item,
            rss_source_feed: event.rss_source_feed
          }

      updated = %{
        popularity
        | score: popularity.score + @score_play,
          plays: popularity.plays + 1,
          plays_people:
            if(is_public,
              do: add_recent_user(popularity.plays_people, event.user_id),
              else: popularity.plays_people
            )
      }

      repo.insert_or_update(
        EpisodePopularity.changeset(updated, %{}),
        on_conflict: :replace_all,
        conflict_target: :rss_source_item
      )
    end)
  end)

  project(%EpisodeSaved{} = event, _metadata, fn multi ->
    # Incrémenter podcast score
    multi =
      Ecto.Multi.run(multi, :podcast_score, fn repo, _changes ->
        popularity =
          repo.get(PodcastPopularity, event.rss_source_feed) ||
            %PodcastPopularity{rss_source_feed: event.rss_source_feed}

        updated = %{popularity | score: popularity.score + @score_save}

        repo.insert_or_update(
          PodcastPopularity.changeset(updated, %{}),
          on_conflict: :replace_all,
          conflict_target: :rss_source_feed
        )
      end)

    # Incrémenter episode likes
    Ecto.Multi.run(multi, :episode_saved, fn repo, _changes ->
      is_public = is_user_public_with_repo?(repo, event.user_id, event.rss_source_feed, event.rss_source_item)

      popularity =
        repo.get(EpisodePopularity, event.rss_source_item) ||
          %EpisodePopularity{
            rss_source_item: event.rss_source_item,
            rss_source_feed: event.rss_source_feed
          }

      updated = %{
        popularity
        | score: popularity.score + @score_save,
          likes: popularity.likes + 1,
          likes_people:
            if(is_public,
              do: add_recent_user(popularity.likes_people, event.user_id),
              else: popularity.likes_people
            )
      }

      repo.insert_or_update(
        EpisodePopularity.changeset(updated, %{}),
        on_conflict: :replace_all,
        conflict_target: :rss_source_item
      )
    end)
  end)

  project(%EpisodeShared{} = event, _metadata, fn multi ->
    # Incrémenter podcast score
    multi =
      Ecto.Multi.run(multi, :podcast_score, fn repo, _changes ->
        popularity =
          repo.get(PodcastPopularity, event.rss_source_feed) ||
            %PodcastPopularity{rss_source_feed: event.rss_source_feed}

        updated = %{popularity | score: popularity.score + @score_share}

        repo.insert_or_update(
          PodcastPopularity.changeset(updated, %{}),
          on_conflict: :replace_all,
          conflict_target: :rss_source_feed
        )
      end)

    # Incrémenter episode score
    Ecto.Multi.run(multi, :episode_shared, fn repo, _changes ->
      popularity =
        repo.get(EpisodePopularity, event.rss_source_item) ||
          %EpisodePopularity{
            rss_source_item: event.rss_source_item,
            rss_source_feed: event.rss_source_feed
          }

      updated = %{popularity | score: popularity.score + @score_share}

      repo.insert_or_update(
        EpisodePopularity.changeset(updated, %{}),
        on_conflict: :replace_all,
        conflict_target: :rss_source_item
      )
    end)
  end)

  project(%PopularityRecalculated{} = event, _metadata, fn multi ->
    # Event émis par le worker après recalcul depuis public_events
    if event.rss_source_item do
      Ecto.Multi.update_all(
        multi,
        :recalc_episode,
        from(e in EpisodePopularity, where: e.rss_source_item == ^event.rss_source_item),
        set: [
          score_previous: event.plays,
          plays_previous: event.plays,
          likes_previous: event.likes,
          updated_at: DateTime.utc_now()
        ]
      )
    else
      Ecto.Multi.update_all(
        multi,
        :recalc_podcast,
        from(p in PodcastPopularity, where: p.rss_source_feed == ^event.rss_source_feed),
        set: [
          score_previous: event.plays,
          plays_previous: event.plays,
          likes_previous: event.likes,
          updated_at: DateTime.utc_now()
        ]
      )
    end
  end)

  defp add_recent_user(people_list, user_id) when is_list(people_list) do
    # Garder les 10 derniers users uniques
    [user_id | Enum.reject(people_list, &(&1 == user_id))]
    |> Enum.take(10)
  end

  defp add_recent_user(_people_list, user_id), do: [user_id]
end
