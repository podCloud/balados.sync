defmodule BaladosSyncProjections.Projectors.CollectionsProjector do
  @moduledoc """
  Projector for Collection events.

  Maintains the collections read model by listening to collection-related events
  and updating the collections and collection_subscriptions tables.
  """

  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "CollectionsProjector",
    start_from: :origin

  require Logger

  alias BaladosSyncProjections.Schemas.{Collection, CollectionSubscription}

  @doc """
  Projects CollectionCreated event to insert a new collection.
  """
  project(%BaladosSyncCore.Events.CollectionCreated{} = event, _metadata, fn multi ->
    Logger.debug("Projecting CollectionCreated for collection_id=#{event.collection_id}")

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

    Ecto.Multi.insert(
      multi,
      :collection,
      changeset,
      on_conflict: {:replace, [:title, :is_default, :description, :color, :updated_at]},
      conflict_target: [:id]
    )
  end)

  @doc """
  Projects FeedAddedToCollection event to insert a collection-feed association.
  Automatically assigns the next available position.
  """
  project(%BaladosSyncCore.Events.FeedAddedToCollection{} = event, _metadata, fn multi ->
    Logger.debug(
      "Projecting FeedAddedToCollection for collection_id=#{event.collection_id}, feed=#{event.rss_source_feed}"
    )

    # Calculate next position
    multi =
      Ecto.Multi.run(multi, :next_position, fn repo, _changes ->
        max_position =
          from(cs in CollectionSubscription,
            where: cs.collection_id == ^event.collection_id,
            select: max(cs.position)
          )
          |> repo.one() || -1

        {:ok, max_position + 1}
      end)

    Ecto.Multi.run(multi, :collection_subscription, fn repo, %{next_position: position} ->
      changeset =
        CollectionSubscription.changeset(%CollectionSubscription{}, %{
          collection_id: event.collection_id,
          rss_source_feed: event.rss_source_feed,
          position: position,
          inserted_at: truncate_timestamp(event.timestamp),
          updated_at: truncate_timestamp(event.timestamp)
        })

      case repo.insert(changeset, on_conflict: :nothing, conflict_target: [:collection_id, :rss_source_feed]) do
        {:ok, record} -> {:ok, record}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end)

  @doc """
  Projects FeedRemovedFromCollection event to delete a collection-feed association.
  """
  project(%BaladosSyncCore.Events.FeedRemovedFromCollection{} = event, _metadata, fn multi ->
    Logger.debug(
      "Projecting FeedRemovedFromCollection for collection_id=#{event.collection_id}, feed=#{event.rss_source_feed}"
    )

    Ecto.Multi.delete_all(
      multi,
      :remove_collection_subscription,
      fn _ ->
        from(cs in CollectionSubscription,
          where:
            cs.collection_id == ^event.collection_id and
              cs.rss_source_feed == ^event.rss_source_feed
        )
      end
    )
  end)

  @doc """
  Projects CollectionUpdated event to update a collection's properties.
  """
  project(%BaladosSyncCore.Events.CollectionUpdated{} = event, _metadata, fn multi ->
    Logger.debug("Projecting CollectionUpdated for collection_id=#{event.collection_id}")

    updates = [updated_at: truncate_timestamp(event.timestamp)]
    updates = if event.title, do: Keyword.put(updates, :title, event.title), else: updates

    updates =
      if event.description,
        do: Keyword.put(updates, :description, event.description),
        else: updates

    updates = if event.color, do: Keyword.put(updates, :color, event.color), else: updates

    Ecto.Multi.update_all(
      multi,
      :update_collection,
      fn _ ->
        from(c in Collection,
          where: c.id == ^event.collection_id
        )
      end,
      set: updates
    )
  end)

  @doc """
  Projects CollectionDeleted event to soft-delete a collection.
  """
  project(%BaladosSyncCore.Events.CollectionDeleted{} = event, _metadata, fn multi ->
    Logger.debug("Projecting CollectionDeleted for collection_id=#{event.collection_id}")

    Ecto.Multi.update_all(
      multi,
      :soft_delete_collection,
      fn _ ->
        from(c in Collection,
          where: c.id == ^event.collection_id
        )
      end,
      set: [
        deleted_at: truncate_timestamp(event.timestamp),
        updated_at: truncate_timestamp(event.timestamp)
      ]
    )
  end)

  @doc """
  Projects CollectionFeedReordered event to update feed positions within a collection.
  """
  project(%BaladosSyncCore.Events.CollectionFeedReordered{} = event, _metadata, fn multi ->
    Logger.debug(
      "Projecting CollectionFeedReordered for collection_id=#{event.collection_id}"
    )

    # Update positions for all feeds in the collection based on feed_order
    Enum.with_index(event.feed_order)
    |> Enum.reduce(multi, fn {feed, position}, acc_multi ->
      Ecto.Multi.update_all(
        acc_multi,
        {:update_position, feed},
        fn _ ->
          from(cs in CollectionSubscription,
            where:
              cs.collection_id == ^event.collection_id and
                cs.rss_source_feed == ^feed
          )
        end,
        set: [position: position, updated_at: truncate_timestamp(event.timestamp)]
      )
    end)
  end)

  @doc """
  Projects CollectionVisibilityChanged event to update a collection's public visibility.
  """
  project(%BaladosSyncCore.Events.CollectionVisibilityChanged{} = event, _metadata, fn multi ->
    Logger.debug(
      "Projecting CollectionVisibilityChanged for collection_id=#{event.collection_id}, is_public=#{event.is_public}"
    )

    Ecto.Multi.update_all(
      multi,
      :update_collection_visibility,
      fn _ ->
        from(c in Collection,
          where: c.id == ^event.collection_id
        )
      end,
      set: [is_public: event.is_public, updated_at: truncate_timestamp(event.timestamp)]
    )
  end)

  # Private functions

  @doc false
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
