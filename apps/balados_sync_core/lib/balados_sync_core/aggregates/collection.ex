defmodule BaladosSyncCore.Aggregates.Collection do
  @moduledoc """
  Collection aggregate for the CQRS/Event Sourcing system.

  Handles creating, updating, deleting collections and managing feed organization.
  Split from the monolithic User aggregate as part of bounded context separation.

  ## Cross-domain Validation

  The `AddFeedToCollection` command requires that the feed is subscribed. Since
  subscription state lives in the Subscription aggregate, this validation is
  handled by `BaladosSyncCore.Middleware.ValidateSubscription` middleware that
  queries the subscriptions projection before the command reaches this aggregate.

  ## State

  - `user_id` - Unique identifier for the user
  - `collections` - Map of `%{collection_id => %{title, is_default, description, color, feed_ids, is_public}}`
  """

  defstruct [
    :user_id,
    # %{collection_id => %{title, is_default, description, color, feed_ids, is_public}}
    :collections
  ]

  alias BaladosSyncCore.Commands.{
    CreateCollection,
    AddFeedToCollection,
    RemoveFeedFromCollection,
    UpdateCollection,
    DeleteCollection,
    ReorderCollectionFeed,
    ChangeCollectionVisibility,
    SnapshotCollection
  }

  alias BaladosSyncCore.Events.{
    CollectionCreated,
    FeedAddedToCollection,
    FeedRemovedFromCollection,
    CollectionUpdated,
    CollectionDeleted,
    CollectionFeedReordered,
    CollectionVisibilityChanged,
    CollectionCheckpoint
  }

  # SnapshotCollection — skip if aggregate has never been initialized
  def execute(%__MODULE__{user_id: nil}, %SnapshotCollection{}), do: []

  def execute(%__MODULE__{} = state, %SnapshotCollection{} = _cmd) do
    %CollectionCheckpoint{
      user_id: state.user_id,
      collections: state.collections || %{},
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # CreateCollection
  def execute(%__MODULE__{user_id: nil}, %CreateCollection{} = cmd) do
    do_create_collection(%{}, cmd)
  end

  def execute(%__MODULE__{} = state, %CreateCollection{} = cmd) do
    do_create_collection(state.collections || %{}, cmd)
  end

  # AddFeedToCollection
  # Note: feed_not_subscribed validation is handled by ValidateSubscription middleware
  def execute(%__MODULE__{} = state, %AddFeedToCollection{} = cmd) do
    collections = state.collections || %{}

    if not Map.has_key?(collections, cmd.collection_id) do
      {:error, :collection_not_found}
    else
      %FeedAddedToCollection{
        user_id: cmd.user_id,
        collection_id: cmd.collection_id,
        rss_source_feed: cmd.rss_source_feed,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        event_infos: cmd.event_infos || %{}
      }
    end
  end

  # RemoveFeedFromCollection
  def execute(%__MODULE__{} = state, %RemoveFeedFromCollection{} = cmd) do
    collections = state.collections || %{}

    if Map.has_key?(collections, cmd.collection_id) do
      %FeedRemovedFromCollection{
        user_id: cmd.user_id,
        collection_id: cmd.collection_id,
        rss_source_feed: cmd.rss_source_feed,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        event_infos: cmd.event_infos || %{}
      }
    else
      {:error, :collection_not_found}
    end
  end

  # UpdateCollection
  def execute(%__MODULE__{} = state, %UpdateCollection{} = cmd) do
    collections = state.collections || %{}

    cond do
      not Map.has_key?(collections, cmd.collection_id) ->
        {:error, :collection_not_found}

      is_nil(cmd.title) && is_nil(cmd.description) && is_nil(cmd.color) ->
        {:error, :no_changes}

      not is_nil(cmd.title) && String.trim(cmd.title) == "" ->
        {:error, :title_required}

      true ->
        %CollectionUpdated{
          user_id: cmd.user_id,
          collection_id: cmd.collection_id,
          title: cmd.title,
          description: cmd.description,
          color: cmd.color,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          event_infos: cmd.event_infos || %{}
        }
    end
  end

  # DeleteCollection
  def execute(%__MODULE__{} = state, %DeleteCollection{} = cmd) do
    collections = state.collections || %{}

    case Map.get(collections, cmd.collection_id) do
      nil ->
        {:error, :collection_not_found}

      collection ->
        if collection.is_default do
          {:error, :cannot_delete_default_collection}
        else
          %CollectionDeleted{
            user_id: cmd.user_id,
            collection_id: cmd.collection_id,
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            event_infos: cmd.event_infos || %{}
          }
        end
    end
  end

  # ReorderCollectionFeed
  def execute(%__MODULE__{} = state, %ReorderCollectionFeed{} = cmd) do
    collections = state.collections || %{}

    case Map.get(collections, cmd.collection_id) do
      nil ->
        {:error, :collection_not_found}

      collection ->
        feed_ids = collection.feed_ids || []

        cond do
          cmd.rss_source_feed not in feed_ids ->
            {:error, :feed_not_in_collection}

          cmd.new_position < 0 or cmd.new_position >= length(feed_ids) ->
            {:error, :invalid_position}

          true ->
            remaining = List.delete(feed_ids, cmd.rss_source_feed)
            new_order = List.insert_at(remaining, cmd.new_position, cmd.rss_source_feed)

            %CollectionFeedReordered{
              user_id: cmd.user_id,
              collection_id: cmd.collection_id,
              rss_source_feed: cmd.rss_source_feed,
              new_position: cmd.new_position,
              feed_order: new_order,
              timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
              event_infos: cmd.event_infos || %{}
            }
        end
    end
  end

  # ChangeCollectionVisibility
  def execute(%__MODULE__{} = state, %ChangeCollectionVisibility{} = cmd) do
    collections = state.collections || %{}

    if Map.has_key?(collections, cmd.collection_id) do
      %CollectionVisibilityChanged{
        user_id: cmd.user_id,
        collection_id: cmd.collection_id,
        is_public: cmd.is_public,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        event_infos: cmd.event_infos || %{}
      }
    else
      {:error, :collection_not_found}
    end
  end

  # Private helpers

  defp do_create_collection(collections, cmd) do
    cond do
      is_nil(cmd.title) || String.trim(cmd.title) == "" ->
        {:error, :title_required}

      cmd.is_default && Enum.any?(collections, fn {_id, col} -> col.is_default end) ->
        {:error, :default_collection_already_exists}

      true ->
        collection_id = cmd.collection_id || Ecto.UUID.generate()

        %CollectionCreated{
          user_id: cmd.user_id,
          collection_id: collection_id,
          title: cmd.title,
          is_default: cmd.is_default,
          is_public: false,
          description: cmd.description,
          color: cmd.color,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          event_infos: cmd.event_infos || %{}
        }
    end
  end

  # Apply events
  def apply(%__MODULE__{} = state, %CollectionCreated{} = event) do
    collections = state.collections || %{}

    new_collection = %{
      title: event.title,
      is_default: event.is_default,
      description: event.description,
      color: event.color,
      feed_ids: [],
      is_public: event.is_public || false
    }

    %{
      state
      | user_id: event.user_id,
        collections: Map.put(collections, event.collection_id, new_collection)
    }
  end

  def apply(%__MODULE__{} = state, %FeedAddedToCollection{} = event) do
    collections = state.collections || %{}

    case Map.get(collections, event.collection_id) do
      nil ->
        state

      collection ->
        feed_ids = collection.feed_ids || []

        updated_feed_ids =
          if event.rss_source_feed in feed_ids,
            do: feed_ids,
            else: feed_ids ++ [event.rss_source_feed]

        updated_collection = %{collection | feed_ids: updated_feed_ids}
        %{state | collections: Map.put(collections, event.collection_id, updated_collection)}
    end
  end

  def apply(%__MODULE__{} = state, %FeedRemovedFromCollection{} = event) do
    collections = state.collections || %{}

    case Map.get(collections, event.collection_id) do
      nil ->
        state

      collection ->
        feed_ids = collection.feed_ids || []
        updated_feed_ids = List.delete(feed_ids, event.rss_source_feed)
        updated_collection = %{collection | feed_ids: updated_feed_ids}
        %{state | collections: Map.put(collections, event.collection_id, updated_collection)}
    end
  end

  def apply(%__MODULE__{} = state, %CollectionUpdated{} = event) do
    collections = state.collections || %{}

    case Map.get(collections, event.collection_id) do
      nil ->
        state

      collection ->
        updated_collection = collection

        updated_collection =
          if not is_nil(event.title),
            do: %{updated_collection | title: event.title},
            else: updated_collection

        updated_collection =
          if not is_nil(event.description),
            do: %{updated_collection | description: event.description},
            else: updated_collection

        updated_collection =
          if not is_nil(event.color),
            do: %{updated_collection | color: event.color},
            else: updated_collection

        %{state | collections: Map.put(collections, event.collection_id, updated_collection)}
    end
  end

  def apply(%__MODULE__{} = state, %CollectionDeleted{} = event) do
    collections = state.collections || %{}
    %{state | collections: Map.delete(collections, event.collection_id)}
  end

  def apply(%__MODULE__{} = state, %CollectionFeedReordered{} = event) do
    collections = state.collections || %{}

    case Map.get(collections, event.collection_id) do
      nil ->
        state

      collection ->
        updated_collection = %{collection | feed_ids: event.feed_order}
        %{state | collections: Map.put(collections, event.collection_id, updated_collection)}
    end
  end

  def apply(%__MODULE__{} = state, %CollectionVisibilityChanged{} = event) do
    collections = state.collections || %{}

    case Map.get(collections, event.collection_id) do
      nil ->
        state

      collection ->
        updated_collection = %{collection | is_public: event.is_public}
        %{state | collections: Map.put(collections, event.collection_id, updated_collection)}
    end
  end

  # Note: Commanded's JsonSerializer deserializes with keys: :atoms,
  # so nested map keys (title, is_default, etc.) are properly atomized.
  def apply(%__MODULE__{} = state, %CollectionCheckpoint{} = event) do
    %{state | user_id: event.user_id, collections: event.collections || %{}}
  end

  def apply(%__MODULE__{} = state, _event), do: state
end
