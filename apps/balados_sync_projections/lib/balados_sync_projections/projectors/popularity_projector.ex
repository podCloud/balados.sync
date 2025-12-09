defmodule BaladosSyncProjections.Projectors.PopularityProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "PopularityProjector"

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    PlayRecorded,
    EpisodeSaved,
    EpisodeShared,
    PopularityRecalculated
  }

  alias BaladosSyncCore.RssCache

  alias BaladosSyncProjections.Schemas.{PodcastPopularity, EpisodePopularity, UserPrivacy}
  alias BaladosSyncProjections.ProjectionsRepo

  # Scores par type d'action
  @score_subscribe 10
  @score_play 5
  @score_save 3
  @score_share 2

  defp is_user_public_with_repo?(repo, user_id, feed, item) do
    # Check with Elixir is_nil to avoid type inference issues with fragments
    item_condition = if is_nil(item), do: true, else: false
    feed_condition = if is_nil(feed), do: true, else: false

    query =
      from(p in UserPrivacy,
        where: p.user_id == ^user_id
      )

    query =
      if item_condition do
        from(p in query, where: is_nil(p.rss_source_item))
      else
        from(p in query, where: p.rss_source_item == ^item or is_nil(p.rss_source_item))
      end

    query =
      if feed_condition do
        from(p in query, where: is_nil(p.rss_source_feed))
      else
        from(p in query, where: p.rss_source_feed == ^feed or is_nil(p.rss_source_feed))
      end

    query =
      from(p in query,
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
    Logger.info(
      "[PopularityProjector] PlayRecorded event: user=#{event.user_id}, feed=#{event.rss_source_feed}, item=#{event.rss_source_item}"
    )

    # Incrémenter podcast popularity
    multi =
      Ecto.Multi.run(multi, :podcast_popularity, fn repo, _changes ->
        try do
          Logger.debug(
            "[PopularityProjector] Processing podcast popularity for feed: #{event.rss_source_feed}"
          )

          is_public =
            is_user_public_with_repo?(
              repo,
              event.user_id,
              event.rss_source_feed,
              event.rss_source_item
            )

          Logger.debug("[PopularityProjector] Is public: #{is_public}")

          popularity =
            repo.get(PodcastPopularity, event.rss_source_feed) ||
              %PodcastPopularity{rss_source_feed: event.rss_source_feed}

          Logger.debug(
            "[PopularityProjector] Current podcast popularity: plays=#{popularity.plays}, score=#{popularity.score}"
          )

          attrs = %{
            rss_source_feed: event.rss_source_feed,
            score: popularity.score + @score_play,
            plays: popularity.plays + 1,
            plays_people:
              if(is_public,
                do: add_recent_user(popularity.plays_people, event.user_id),
                else: popularity.plays_people
              )
          }

          Logger.debug(
            "[PopularityProjector] Updated podcast popularity: plays=#{attrs.plays}, score=#{attrs.score}"
          )

          result =
            repo.insert_or_update(
              PodcastPopularity.changeset(popularity, attrs),
              on_conflict: :replace_all,
              conflict_target: :rss_source_feed
            )

          case result do
            {:ok, data} ->
              Logger.info(
                "[PopularityProjector] Podcast popularity updated successfully: plays=#{data.plays}, score=#{data.score}"
              )

              {:ok, result}

            {:error, reason} ->
              Logger.error(
                "[PopularityProjector] Failed to update podcast popularity: #{inspect(reason)}"
              )

              {:error, reason}
          end
        rescue
          error in RuntimeError ->
            Logger.error(
              "[PopularityProjector] RuntimeError updating podcast popularity: #{error.message}"
            )

            {:error, :runtime_error}

          error ->
            Logger.error(
              "[PopularityProjector] Unexpected exception updating podcast popularity: #{Exception.format(:error, error)}"
            )

            {:error, :unexpected_error}
        end
      end)

    # Incrémenter episode popularity
    multi =
      Ecto.Multi.run(multi, :episode_popularity, fn repo, _changes ->
        try do
          Logger.debug(
            "[PopularityProjector] Processing episode popularity for item: #{event.rss_source_item}"
          )

          is_public =
            is_user_public_with_repo?(
              repo,
              event.user_id,
              event.rss_source_feed,
              event.rss_source_item
            )

          Logger.debug("[PopularityProjector] Episode is public: #{is_public}")

          popularity =
            repo.get(EpisodePopularity, event.rss_source_item) ||
              %EpisodePopularity{
                rss_source_item: event.rss_source_item,
                rss_source_feed: event.rss_source_feed
              }

          Logger.debug(
            "[PopularityProjector] Current episode popularity: plays=#{popularity.plays}, score=#{popularity.score}"
          )

          attrs = %{
            rss_source_item: event.rss_source_item,
            rss_source_feed: event.rss_source_feed,
            score: popularity.score + @score_play,
            plays: popularity.plays + 1,
            plays_people:
              if(is_public,
                do: add_recent_user(popularity.plays_people, event.user_id),
                else: popularity.plays_people
              )
          }

          Logger.debug(
            "[PopularityProjector] Updated episode popularity: plays=#{attrs.plays}, score=#{attrs.score}"
          )

          result =
            repo.insert_or_update(
              EpisodePopularity.changeset(popularity, attrs),
              on_conflict: :replace_all,
              conflict_target: :rss_source_item
            )

          case result do
            {:ok, data} ->
              Logger.info(
                "[PopularityProjector] Episode popularity updated successfully: item=#{event.rss_source_item}, plays=#{data.plays}, score=#{data.score}"
              )

              {:ok, result}

            {:error, reason} ->
              Logger.error(
                "[PopularityProjector] Failed to update episode popularity: #{inspect(reason)}"
              )

              {:error, reason}
          end
        rescue
          error in RuntimeError ->
            Logger.error(
              "[PopularityProjector] RuntimeError updating episode popularity: #{error.message}"
            )

            {:error, :runtime_error}

          error ->
            Logger.error(
              "[PopularityProjector] Unexpected exception updating episode popularity: #{Exception.format(:error, error)}"
            )

            {:error, :unexpected_error}
        end
      end)

    # Enrichir async avec les métadonnées de l'épisode
    # Lancer le Task APRÈS que la transaction soit complète (ne pas bloquer)
    multi =
      Ecto.Multi.run(multi, :enrich_metadata, fn _repo, _changes ->
        Logger.debug(
          "[PopularityProjector] Starting async metadata enrichment for item: #{event.rss_source_item}"
        )

        Task.start(fn ->
          enrich_episode_metadata_async(event.rss_source_feed, event.rss_source_item)
        end)

        {:ok, :enriched}
      end)

    multi
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
      is_public =
        is_user_public_with_repo?(
          repo,
          event.user_id,
          event.rss_source_feed,
          event.rss_source_item
        )

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

  # Enrichir async les métadonnées d'épisode depuis le RSS (source de vérité)
  defp enrich_episode_metadata_async(encoded_feed, encoded_item) do
    try do
      Logger.debug(
        "[PopularityProjector] Enriching metadata: feed=#{encoded_feed}, item=#{encoded_item}"
      )

      # Décoder les IDs
      feed_url = Base.url_decode64!(encoded_feed, padding: false)
      decoded_item = Base.url_decode64!(encoded_item, padding: false)
      Logger.debug("[PopularityProjector] Decoded feed_url=#{feed_url}, item=#{decoded_item}")

      case String.split(decoded_item, ",", parts: 2) do
        [guid, _enclosure_url] ->
          Logger.debug("[PopularityProjector] Looking for episode with guid=#{guid}")

          # Récupérer et parser le RSS
          case RssCache.fetch_and_parse_feed(feed_url) do
            {:ok, {feed_metadata, episodes}} ->
              Logger.debug(
                "[PopularityProjector] Successfully fetched RSS: #{feed_metadata.title}, #{length(episodes)} episodes"
              )

              # Trouver l'épisode
              case Enum.find(episodes, &(&1.guid == guid)) do
                nil ->
                  Logger.warning(
                    "[PopularityProjector] Episode with guid=#{guid} not found in RSS feed"
                  )

                  :ok

                episode ->
                  Logger.info("[PopularityProjector] Found episode: #{episode.title}")
                  # Mettre à jour la projection avec les métadonnées du RSS
                  update_episode_metadata(encoded_feed, encoded_item, episode, feed_metadata)
              end

            {:error, reason} ->
              Logger.error(
                "[PopularityProjector] Failed to fetch RSS from #{feed_url}: #{inspect(reason)}"
              )

              :ok
          end

        _ ->
          Logger.error("[PopularityProjector] Invalid item format: #{decoded_item}")
          :ok
      end
    rescue
      error ->
        Logger.error(
          "[PopularityProjector] Exception during metadata enrichment: #{inspect(error)}"
        )

        :ok
    end
  end

  defp update_episode_metadata(encoded_feed, encoded_item, episode, feed_metadata) do
    try do
      Logger.debug("[PopularityProjector] Updating metadata for item=#{encoded_item}")

      popularity =
        ProjectionsRepo.get(EpisodePopularity, encoded_item) ||
          %EpisodePopularity{
            rss_source_item: encoded_item,
            rss_source_feed: encoded_feed
          }

      # Toujours mettre à jour avec les données du RSS (source de vérité)
      # Normalize cover format: RssParser returns cover as a string URL for episodes
      # We normalize it to map format {src, srcset} for consistency with feed-level covers
      # Defensive coding: also handles cases where cover might already be a map
      episode_cover_map = normalize_cover(episode.cover)

      # Extract episode link (prefer episode.link, fallback to enclosure.url)
      episode_link = episode.link || (episode.enclosure && episode.enclosure.url)

      attrs = %{
        rss_source_item: encoded_item,
        rss_source_feed: encoded_feed,
        episode_title: episode.title,
        episode_author: episode.author,
        episode_description: episode.description,
        episode_cover: episode_cover_map,
        episode_link: episode_link,
        podcast_title: feed_metadata.title
      }

      result =
        ProjectionsRepo.insert_or_update(
          EpisodePopularity.changeset(popularity, attrs),
          on_conflict: :replace_all,
          conflict_target: :rss_source_item
        )

      case result do
        {:ok, _} ->
          Logger.info(
            "[PopularityProjector] Metadata enrichment successful: title=#{episode.title}"
          )

        {:error, reason} ->
          Logger.error("[PopularityProjector] Failed to update metadata: #{inspect(reason)}")
      end

      result
    rescue
      error ->
        Logger.error("[PopularityProjector] Exception updating metadata: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc false
  defp normalize_cover(cover) when is_binary(cover) do
    # Convert string URL to map format
    %{src: cover, srcset: nil}
  end

  defp normalize_cover(cover) when is_map(cover) do
    # Already in map format (defensive against different sources)
    cover
  end

  defp normalize_cover(_), do: nil
end
