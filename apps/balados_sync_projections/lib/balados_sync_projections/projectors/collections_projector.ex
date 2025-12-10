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

    changeset = Collection.changeset(%Collection{}, %{
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
  """
  project(%BaladosSyncCore.Events.FeedAddedToCollection{} = event, _metadata, fn multi ->
    Logger.debug(
      "Projecting FeedAddedToCollection for collection_id=#{event.collection_id}, feed=#{event.rss_source_feed}"
    )

    changeset =
      CollectionSubscription.changeset(%CollectionSubscription{}, %{
        collection_id: event.collection_id,
        rss_source_feed: event.rss_source_feed,
        inserted_at: truncate_timestamp(event.timestamp),
        updated_at: truncate_timestamp(event.timestamp)
      })

    Ecto.Multi.insert(
      multi,
      :collection_subscription,
      changeset,
      on_conflict: :nothing,
      conflict_target: [:collection_id, :rss_source_feed]
    )
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
    updates = if event.description, do: Keyword.put(updates, :description, event.description), else: updates
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
