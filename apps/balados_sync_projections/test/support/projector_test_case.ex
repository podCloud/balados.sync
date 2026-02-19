defmodule BaladosSyncProjections.ProjectorTestCase do
  @moduledoc """
  Test support module for testing CQRS/ES projector logic.

  This module provides helpers for testing projectors by manually applying events
  and verifying the resulting projections. This approach is necessary because:

  1. Commanded projectors run in separate GenServer processes
  2. Ecto Sandbox cannot be shared with external processes reliably
  3. The In-Memory EventStore + projector subscription + sandbox isolation
     creates complex interactions that are difficult to test

  ## Usage

      use BaladosSyncProjections.ProjectorTestCase

      test "UserSubscribed creates subscription projection" do
        event = %UserSubscribed{
          user_id: uuid(),
          rss_source_feed: encode_feed("https://example.com/feed.xml"),
          subscribed_at: now()
        }

        assert {:ok, _} = apply_event(event)

        subscription = ProjectionsRepo.get_by(Subscription, user_id: event.user_id)
        assert subscription.rss_source_feed == event.rss_source_feed
      end

  ## Test Strategy

  These tests verify:
  - Event → Projection mapping correctness
  - Idempotency (replay safety)
  - Partial updates (only non-nil fields)
  - Cascade effects (soft deletes, etc.)
  - Multi-user isolation

  The full CQRS flow (Command → Event → Projector → Projection) is validated by:
  - `in_memory_dispatch_test.exs` verifies command dispatch works
  - These tests verify projector logic works
  - Together they prove the complete flow
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use BaladosSyncProjections.DataCase

      import BaladosSyncProjections.ProjectorTestCase

      alias BaladosSyncProjections.ProjectionsRepo

      # Events
      alias BaladosSyncCore.Events.{
        # Subscriptions
        UserSubscribed,
        UserUnsubscribed,
        UserCheckpoint,
        # Play statuses
        PlayRecorded,
        PositionUpdated,
        # Playlists
        PlaylistCreated,
        PlaylistDeleted,
        PlaylistUpdated,
        PlaylistReordered,
        PlaylistVisibilityChanged,
        EpisodeSaved,
        EpisodeUnsaved,
        # Collections
        CollectionCreated,
        CollectionDeleted,
        CollectionUpdated,
        CollectionFeedReordered,
        CollectionVisibilityChanged,
        FeedAddedToCollection,
        FeedRemovedFromCollection,
        # Likes
        PodcastLiked,
        PodcastUnliked,
        EpisodeLiked,
        EpisodeUnliked,
        LikeCheckpoint,
        # Public events / Privacy
        PrivacyChanged,
        EventsRemoved
      }

      # Schemas
      alias BaladosSyncProjections.Schemas.{
        Subscription,
        PlayStatus,
        Playlist,
        PlaylistItem,
        Collection,
        CollectionSubscription,
        PublicEvent,
        UserPrivacy,
        UserLike,
        PodcastPopularity,
        EpisodePopularity
      }
    end
  end

  @doc """
  Apply an event to the projections database.

  This function replicates the projector's database logic for testing purposes.
  It uses the same Ecto operations (insert, upsert, update_all) as the actual
  projectors, ensuring test behavior matches production behavior.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def apply_event(event) do
    alias BaladosSyncProjections.ProjectionsRepo

    case event do
      %BaladosSyncCore.Events.UserSubscribed{} ->
        apply_user_subscribed(event, ProjectionsRepo)

      %BaladosSyncCore.Events.UserUnsubscribed{} ->
        apply_user_unsubscribed(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PlayRecorded{} ->
        apply_play_recorded(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PositionUpdated{} ->
        apply_position_updated(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PlaylistCreated{} ->
        apply_playlist_created(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PlaylistDeleted{} ->
        apply_playlist_deleted(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PlaylistUpdated{} ->
        apply_playlist_updated(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PlaylistVisibilityChanged{} ->
        apply_playlist_visibility_changed(event, ProjectionsRepo)

      %BaladosSyncCore.Events.EpisodeSaved{} ->
        apply_episode_saved(event, ProjectionsRepo)

      %BaladosSyncCore.Events.EpisodeUnsaved{} ->
        apply_episode_unsaved(event, ProjectionsRepo)

      %BaladosSyncCore.Events.CollectionCreated{} ->
        apply_collection_created(event, ProjectionsRepo)

      %BaladosSyncCore.Events.CollectionDeleted{} ->
        apply_collection_deleted(event, ProjectionsRepo)

      %BaladosSyncCore.Events.CollectionUpdated{} ->
        apply_collection_updated(event, ProjectionsRepo)

      %BaladosSyncCore.Events.CollectionVisibilityChanged{} ->
        apply_collection_visibility_changed(event, ProjectionsRepo)

      %BaladosSyncCore.Events.FeedAddedToCollection{} ->
        apply_feed_added_to_collection(event, ProjectionsRepo)

      %BaladosSyncCore.Events.FeedRemovedFromCollection{} ->
        apply_feed_removed_from_collection(event, ProjectionsRepo)

      %BaladosSyncCore.Events.CollectionFeedReordered{} ->
        apply_collection_feed_reordered(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PodcastLiked{} ->
        apply_podcast_liked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PodcastUnliked{} ->
        apply_podcast_unliked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.EpisodeLiked{} ->
        apply_episode_liked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.EpisodeUnliked{} ->
        apply_episode_unliked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.LikeCheckpoint{} ->
        apply_like_checkpoint(event, ProjectionsRepo)

      _ ->
        {:error, {:unsupported_event, event.__struct__}}
    end
  end

  @doc """
  Apply an event to the popularity projections.

  Separate from `apply_event` because popularity projections are handled by
  a different projector (PopularityProjector) and require different schemas.
  """
  def apply_popularity_event(event) do
    alias BaladosSyncProjections.ProjectionsRepo

    case event do
      %BaladosSyncCore.Events.PodcastLiked{} ->
        apply_popularity_podcast_liked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.PodcastUnliked{} ->
        apply_popularity_podcast_unliked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.EpisodeLiked{} ->
        apply_popularity_episode_liked(event, ProjectionsRepo)

      %BaladosSyncCore.Events.EpisodeUnliked{} ->
        apply_popularity_episode_unliked(event, ProjectionsRepo)

      _ ->
        {:error, {:unsupported_popularity_event, event.__struct__}}
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc "Generate a random UUID"
  def uuid, do: Ecto.UUID.generate()

  @doc "Get current time truncated to seconds (matches Ecto :utc_datetime)"
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "Encode a feed URL as base64 (matches application convention)"
  def encode_feed(url), do: Base.encode64(url)

  @doc "Encode an episode identifier as base64"
  def encode_item(guid, url \\ nil) do
    if url do
      Base.encode64("#{guid},#{url}")
    else
      Base.encode64(guid)
    end
  end

  # ============================================================================
  # Subscription Projector Logic
  # ============================================================================

  defp apply_user_subscribed(event, repo) do
    alias BaladosSyncProjections.Schemas.Subscription

    repo.insert(
      %Subscription{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_id: event.rss_source_id,
        subscribed_at: parse_datetime(event.subscribed_at),
        unsubscribed_at: nil
      },
      on_conflict: {:replace, [:subscribed_at, :unsubscribed_at, :rss_source_id, :updated_at]},
      conflict_target: [:user_id, :rss_source_feed]
    )
  end

  defp apply_user_unsubscribed(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.Subscription

    {count, _} =
      repo.update_all(
        from(s in Subscription,
          where: s.user_id == ^event.user_id and s.rss_source_feed == ^event.rss_source_feed
        ),
        set: [unsubscribed_at: event.unsubscribed_at, updated_at: DateTime.utc_now()]
      )

    {:ok, %{updated: count}}
  end

  # ============================================================================
  # PlayStatus Projector Logic
  # ============================================================================

  defp apply_play_recorded(event, repo) do
    alias BaladosSyncProjections.Schemas.PlayStatus

    repo.insert(
      %PlayStatus{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        position: event.position,
        played: event.played,
        updated_at: parse_datetime(event.timestamp)
      },
      on_conflict: {:replace, [:position, :played, :updated_at, :rss_source_feed]},
      conflict_target: [:user_id, :rss_source_item]
    )
  end

  defp apply_position_updated(event, repo) do
    alias BaladosSyncProjections.Schemas.PlayStatus

    repo.insert(
      %PlayStatus{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        position: event.position,
        updated_at: parse_datetime(event.timestamp)
      },
      on_conflict: [
        set: [
          position: event.position,
          updated_at: parse_datetime(event.timestamp),
          rss_source_feed: event.rss_source_feed
        ]
      ],
      conflict_target: [:user_id, :rss_source_item]
    )
  end

  # ============================================================================
  # Playlist Projector Logic
  # ============================================================================

  defp apply_playlist_created(event, repo) do
    alias BaladosSyncProjections.Schemas.Playlist

    playlist_attrs = %{
      id: event.playlist_id,
      user_id: event.user_id,
      name: event.name,
      description: event.description,
      type: event.playlist_type || "playlist"
    }

    repo.insert(
      %Playlist{} |> Ecto.Changeset.change(playlist_attrs),
      on_conflict: {:replace, [:name, :description, :type, :updated_at]},
      conflict_target: [:id, :user_id]
    )
  end

  defp apply_playlist_deleted(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.{Playlist, PlaylistItem}

    now = DateTime.utc_now()

    # Soft delete playlist
    {playlist_count, _} =
      repo.update_all(
        from(p in Playlist,
          where: p.id == ^event.playlist_id and p.user_id == ^event.user_id
        ),
        set: [deleted_at: now, updated_at: now]
      )

    # Soft delete all items
    {items_count, _} =
      repo.update_all(
        from(pi in PlaylistItem,
          where: pi.playlist_id == ^event.playlist_id and pi.user_id == ^event.user_id
        ),
        set: [deleted_at: now, updated_at: now]
      )

    {:ok, %{playlist_deleted: playlist_count, items_deleted: items_count}}
  end

  defp apply_playlist_updated(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.Playlist

    updates = []
    updates = if event.name, do: updates ++ [name: event.name], else: updates
    updates = if event.description, do: updates ++ [description: event.description], else: updates
    updates = updates ++ [updated_at: DateTime.utc_now()]

    {count, _} =
      repo.update_all(
        from(p in Playlist,
          where: p.id == ^event.playlist and p.user_id == ^event.user_id
        ),
        set: updates
      )

    {:ok, %{updated: count}}
  end

  defp apply_playlist_visibility_changed(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.Playlist

    {count, _} =
      repo.update_all(
        from(p in Playlist,
          where: p.id == ^event.playlist_id and p.user_id == ^event.user_id
        ),
        set: [is_public: event.is_public, updated_at: DateTime.utc_now()]
      )

    {:ok, %{updated: count}}
  end

  defp apply_episode_saved(event, repo) do
    alias BaladosSyncProjections.Schemas.{Playlist, PlaylistItem}

    # Upsert playlist
    {:ok, _playlist} =
      repo.insert(
        %Playlist{}
        |> Ecto.Changeset.change(%{
          id: event.playlist,
          user_id: event.user_id,
          name: event.playlist
        }),
        on_conflict: {:replace, [:name, :updated_at]},
        conflict_target: [:id, :user_id]
      )

    # Add item
    repo.insert(
      %PlaylistItem{}
      |> Ecto.Changeset.change(%{
        user_id: event.user_id,
        playlist_id: event.playlist,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        item_title: event.item_title,
        feed_title: event.feed_title
      }),
      on_conflict: {:replace, [:item_title, :feed_title, :updated_at]},
      conflict_target: [:playlist_id, :rss_source_feed, :rss_source_item, :user_id]
    )
  end

  defp apply_episode_unsaved(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.PlaylistItem

    {count, _} =
      repo.update_all(
        from(pi in PlaylistItem,
          where:
            pi.user_id == ^event.user_id and
              pi.playlist_id == ^event.playlist and
              pi.rss_source_feed == ^event.rss_source_feed and
              pi.rss_source_item == ^event.rss_source_item
        ),
        set: [deleted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()]
      )

    {:ok, %{deleted: count}}
  end

  # ============================================================================
  # Collection Projector Logic
  # ============================================================================

  defp apply_collection_created(event, repo) do
    alias BaladosSyncProjections.Schemas.Collection

    changeset =
      Collection.changeset(%Collection{}, %{
        id: event.collection_id,
        user_id: event.user_id,
        title: event.title,
        is_default: event.is_default,
        description: event.description,
        color: event.color,
        inserted_at: truncate_timestamp(event.timestamp),
        updated_at: truncate_timestamp(event.timestamp)
      })

    repo.insert(
      changeset,
      on_conflict: {:replace, [:title, :is_default, :description, :color, :updated_at]},
      conflict_target: [:id]
    )
  end

  defp apply_collection_deleted(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.Collection

    timestamp = truncate_timestamp(event.timestamp)

    {count, _} =
      repo.update_all(
        from(c in Collection, where: c.id == ^event.collection_id),
        set: [deleted_at: timestamp, updated_at: timestamp]
      )

    {:ok, %{deleted: count}}
  end

  defp apply_collection_updated(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.Collection

    updates = [updated_at: truncate_timestamp(event.timestamp)]
    updates = if event.title, do: Keyword.put(updates, :title, event.title), else: updates

    updates =
      if event.description,
        do: Keyword.put(updates, :description, event.description),
        else: updates

    updates = if event.color, do: Keyword.put(updates, :color, event.color), else: updates

    {count, _} =
      repo.update_all(
        from(c in Collection, where: c.id == ^event.collection_id),
        set: updates
      )

    {:ok, %{updated: count}}
  end

  defp apply_collection_visibility_changed(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.Collection

    {count, _} =
      repo.update_all(
        from(c in Collection, where: c.id == ^event.collection_id),
        set: [is_public: event.is_public, updated_at: truncate_timestamp(event.timestamp)]
      )

    {:ok, %{updated: count}}
  end

  defp apply_feed_added_to_collection(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.CollectionSubscription

    # Calculate next position
    max_position =
      from(cs in CollectionSubscription,
        where: cs.collection_id == ^event.collection_id,
        select: max(cs.position)
      )
      |> repo.one() || -1

    position = max_position + 1

    changeset =
      CollectionSubscription.changeset(%CollectionSubscription{}, %{
        collection_id: event.collection_id,
        rss_source_feed: event.rss_source_feed,
        position: position,
        inserted_at: truncate_timestamp(event.timestamp),
        updated_at: truncate_timestamp(event.timestamp)
      })

    repo.insert(changeset,
      on_conflict: :nothing,
      conflict_target: [:collection_id, :rss_source_feed]
    )
  end

  defp apply_feed_removed_from_collection(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.CollectionSubscription

    {count, _} =
      repo.delete_all(
        from(cs in CollectionSubscription,
          where:
            cs.collection_id == ^event.collection_id and
              cs.rss_source_feed == ^event.rss_source_feed
        )
      )

    {:ok, %{deleted: count}}
  end

  defp apply_collection_feed_reordered(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.CollectionSubscription

    timestamp = truncate_timestamp(event.timestamp)

    results =
      event.feed_order
      |> Enum.with_index()
      |> Enum.map(fn {feed, position} ->
        {count, _} =
          repo.update_all(
            from(cs in CollectionSubscription,
              where:
                cs.collection_id == ^event.collection_id and
                  cs.rss_source_feed == ^feed
            ),
            set: [position: position, updated_at: timestamp]
          )

        {feed, count}
      end)

    {:ok, %{reordered: results}}
  end

  # ============================================================================
  # Like Projector Logic
  # ============================================================================

  defp apply_podcast_liked(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.UserLike

    existing =
      from(ul in UserLike,
        where:
          ul.user_id == ^event.user_id and ul.rss_source_feed == ^event.rss_source_feed and
            is_nil(ul.rss_source_item)
      )
      |> repo.one()

    case existing do
      nil ->
        repo.insert(%UserLike{
          user_id: event.user_id,
          rss_source_feed: event.rss_source_feed,
          rss_source_item: nil,
          liked_at: event.liked_at,
          unliked_at: nil
        })

      like ->
        like
        |> Ecto.Changeset.change(%{liked_at: event.liked_at, unliked_at: nil})
        |> repo.update()
    end
  end

  defp apply_podcast_unliked(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.UserLike

    existing =
      from(ul in UserLike,
        where:
          ul.user_id == ^event.user_id and ul.rss_source_feed == ^event.rss_source_feed and
            is_nil(ul.rss_source_item)
      )
      |> repo.one()

    case existing do
      nil ->
        {:ok, nil}

      like ->
        like
        |> Ecto.Changeset.change(%{unliked_at: event.unliked_at})
        |> repo.update()
    end
  end

  defp apply_episode_liked(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.UserLike

    existing =
      from(ul in UserLike,
        where:
          ul.user_id == ^event.user_id and ul.rss_source_feed == ^event.rss_source_feed and
            ul.rss_source_item == ^event.rss_source_item
      )
      |> repo.one()

    case existing do
      nil ->
        repo.insert(%UserLike{
          user_id: event.user_id,
          rss_source_feed: event.rss_source_feed,
          rss_source_item: event.rss_source_item,
          liked_at: event.liked_at,
          unliked_at: nil
        })

      like ->
        like
        |> Ecto.Changeset.change(%{liked_at: event.liked_at, unliked_at: nil})
        |> repo.update()
    end
  end

  defp apply_episode_unliked(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.UserLike

    existing =
      from(ul in UserLike,
        where:
          ul.user_id == ^event.user_id and ul.rss_source_feed == ^event.rss_source_feed and
            ul.rss_source_item == ^event.rss_source_item
      )
      |> repo.one()

    case existing do
      nil ->
        {:ok, nil}

      like ->
        like
        |> Ecto.Changeset.change(%{unliked_at: event.unliked_at})
        |> repo.update()
    end
  end

  defp apply_like_checkpoint(event, repo) do
    import Ecto.Query
    alias BaladosSyncProjections.Schemas.UserLike

    # Delete all existing likes for this user
    from(ul in UserLike, where: ul.user_id == ^event.user_id)
    |> repo.delete_all()

    podcast_likes = event.podcast_likes || %{}
    episode_likes = event.episode_likes || %{}

    # Re-insert podcast likes
    for {feed, like_data} <- podcast_likes do
      attrs = %{
        user_id: event.user_id,
        rss_source_feed: feed,
        rss_source_item: nil,
        liked_at: like_data.liked_at,
        unliked_at: like_data[:unliked_at]
      }

      repo.insert!(%UserLike{} |> Ecto.Changeset.change(attrs))
    end

    # Re-insert episode likes
    for {item, like_data} <- episode_likes do
      attrs = %{
        user_id: event.user_id,
        rss_source_feed: like_data.rss_source_feed,
        rss_source_item: item,
        liked_at: like_data.liked_at,
        unliked_at: like_data[:unliked_at]
      }

      repo.insert!(%UserLike{} |> Ecto.Changeset.change(attrs))
    end

    {:ok, :checkpoint_applied}
  end

  # ============================================================================
  # Popularity Projector Logic (Like events)
  # ============================================================================

  @score_like 7

  defp apply_popularity_podcast_liked(event, repo) do
    alias BaladosSyncProjections.Schemas.PodcastPopularity

    popularity =
      repo.get(PodcastPopularity, event.rss_source_feed) ||
        %PodcastPopularity{rss_source_feed: event.rss_source_feed}

    attrs = %{
      rss_source_feed: event.rss_source_feed,
      score: popularity.score + @score_like,
      likes: popularity.likes + 1,
      likes_people: add_recent_user(popularity.likes_people, event.user_id)
    }

    repo.insert_or_update(
      PodcastPopularity.changeset(popularity, attrs),
      on_conflict: :replace_all,
      conflict_target: :rss_source_feed
    )
  end

  defp apply_popularity_podcast_unliked(event, repo) do
    alias BaladosSyncProjections.Schemas.PodcastPopularity

    case repo.get(PodcastPopularity, event.rss_source_feed) do
      nil ->
        {:ok, nil}

      popularity ->
        attrs = %{
          score: max(popularity.score - @score_like, 0),
          likes: max(popularity.likes - 1, 0),
          likes_people: Enum.reject(popularity.likes_people || [], &(&1 == event.user_id))
        }

        repo.insert_or_update(
          PodcastPopularity.changeset(popularity, attrs),
          on_conflict: :replace_all,
          conflict_target: :rss_source_feed
        )
    end
  end

  defp apply_popularity_episode_liked(event, repo) do
    alias BaladosSyncProjections.Schemas.{EpisodePopularity, PodcastPopularity}

    # Episode popularity
    episode_pop =
      repo.get(EpisodePopularity, event.rss_source_item) ||
        %EpisodePopularity{
          rss_source_item: event.rss_source_item,
          rss_source_feed: event.rss_source_feed
        }

    episode_attrs = %{
      rss_source_item: event.rss_source_item,
      rss_source_feed: event.rss_source_feed,
      score: episode_pop.score + @score_like,
      likes: episode_pop.likes + 1,
      likes_people: add_recent_user(episode_pop.likes_people, event.user_id)
    }

    {:ok, _} =
      repo.insert_or_update(
        EpisodePopularity.changeset(episode_pop, episode_attrs),
        on_conflict: :replace_all,
        conflict_target: :rss_source_item
      )

    # Also increment podcast score
    podcast_pop =
      repo.get(PodcastPopularity, event.rss_source_feed) ||
        %PodcastPopularity{rss_source_feed: event.rss_source_feed}

    podcast_attrs = %{
      rss_source_feed: event.rss_source_feed,
      score: podcast_pop.score + @score_like
    }

    repo.insert_or_update(
      PodcastPopularity.changeset(podcast_pop, podcast_attrs),
      on_conflict: :replace_all,
      conflict_target: :rss_source_feed
    )
  end

  defp apply_popularity_episode_unliked(event, repo) do
    alias BaladosSyncProjections.Schemas.{EpisodePopularity, PodcastPopularity}

    # Episode popularity
    case repo.get(EpisodePopularity, event.rss_source_item) do
      nil ->
        :ok

      episode_pop ->
        attrs = %{
          score: max(episode_pop.score - @score_like, 0),
          likes: max(episode_pop.likes - 1, 0),
          likes_people: Enum.reject(episode_pop.likes_people || [], &(&1 == event.user_id))
        }

        {:ok, _} =
          repo.insert_or_update(
            EpisodePopularity.changeset(episode_pop, attrs),
            on_conflict: :replace_all,
            conflict_target: :rss_source_item
          )
    end

    # Also decrement podcast score
    case repo.get(PodcastPopularity, event.rss_source_feed) do
      nil ->
        {:ok, nil}

      podcast_pop ->
        attrs = %{score: max(podcast_pop.score - @score_like, 0)}

        repo.insert_or_update(
          PodcastPopularity.changeset(podcast_pop, attrs),
          on_conflict: :replace_all,
          conflict_target: :rss_source_feed
        )
    end
  end

  defp add_recent_user(people_list, user_id) when is_list(people_list) do
    [user_id | Enum.reject(people_list, &(&1 == user_id))]
    |> Enum.take(10)
  end

  defp add_recent_user(_people_list, user_id), do: [user_id]

  # ============================================================================
  # DateTime Helpers
  # ============================================================================

  defp parse_datetime(nil), do: nil

  defp parse_datetime(%DateTime{} = dt) do
    DateTime.truncate(dt, :second)
  end

  defp parse_datetime(dt_string) when is_binary(dt_string) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _} -> nil
    end
  end

  defp truncate_timestamp(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp truncate_timestamp(%DateTime{} = dt) do
    DateTime.truncate(dt, :second)
  end

  defp truncate_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end
end
