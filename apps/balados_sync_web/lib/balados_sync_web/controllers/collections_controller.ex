defmodule BaladosSyncWeb.CollectionsController do
  @moduledoc """
  Controller for managing user collections.

  Collections allow users to organize their podcast subscriptions into custom groupings.
  All operations use CQRS commands dispatched through the Commanded dispatcher, ensuring
  events are properly recorded in the event store.

  ## Routes

  - `GET /api/v1/collections` - List all collections for the authenticated user
  - `POST /api/v1/collections` - Create a new collection
  - `PATCH /api/v1/collections/:id` - Update a collection
  - `DELETE /api/v1/collections/:id` - Delete a collection (soft delete)
  - `POST /api/v1/collections/:id/feeds` - Add a feed to a collection
  - `DELETE /api/v1/collections/:id/feeds/:feed_id` - Remove a feed from a collection

  ## Authentication

  All endpoints require JWT authentication with appropriate scopes:
  - `user.collections.read` - Read collections
  - `user.collections.write` - Create, update, delete collections and manage feeds

  ## Authorization

  - Users can only access their own collections
  - Default collection (slug: "all") cannot be deleted
  - Feeds can only be added if user is subscribed to them
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher

  alias BaladosSyncCore.Commands.{
    CreateCollection,
    UpdateCollection,
    DeleteCollection,
    AddFeedToCollection,
    RemoveFeedFromCollection
  }

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Collection, Subscription}
  alias BaladosSyncWeb.Plugs.JWTAuth
  import Ecto.Query

  # Scope requirements for collection management
  plug JWTAuth, [scopes: ["user.collections.read"]] when action in [:index, :show]

  plug JWTAuth,
       [scopes: ["user.collections.write"]]
       when action in [:create, :update, :delete, :add_feed, :remove_feed]

  @doc """
  Lists all collections for the authenticated user.

  Returns collections sorted by creation date. Each collection includes the list of
  associated feeds.

  ## Example Request

      GET /api/v1/collections
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response

      {
        "collections": [
          {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "user-123",
            "title": "News",
            "slug": "news",
            "feeds": [
              {
                "id": "550e8400-e29b-41d4-a716-446655440001",
                "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9uZXdz",
                "rss_feed_title": "Morning News"
              }
            ],
            "inserted_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T10:30:00Z"
          }
        ]
      }
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user_id

    collections =
      from(c in Collection,
        where: c.user_id == ^user_id,
        where: is_nil(c.deleted_at),
        order_by: [asc: c.inserted_at],
        preload: [collection_subscriptions: :subscription]
      )
      |> ProjectionsRepo.all()
      |> Enum.map(&format_collection/1)

    json(conn, %{collections: collections})
  end

  @doc """
  Shows a single collection with its feeds.

  Returns the collection details with all associated feeds.

  ## Parameters

  - `id` - Collection ID (UUID)

  ## Example Request

      GET /api/v1/collections/550e8400-e29b-41d4-a716-446655440000
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response (Success)

      {
        "collection": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "user_id": "user-123",
          "title": "News",
          "slug": "news",
          "feeds": [...]
        }
      }

  ## Example Response (Error)

      {
        "error": "not_found"
      }
  """
  def show(conn, %{"id" => collection_id}) do
    user_id = conn.assigns.current_user_id

    case ProjectionsRepo.get(Collection, collection_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      collection ->
        if collection.user_id == user_id && is_nil(collection.deleted_at) do
          collection =
            ProjectionsRepo.preload(collection, collection_subscriptions: :subscription)

          json(conn, %{collection: format_collection(collection)})
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
        end
    end
  end

  @doc """
  Creates a new collection.

  Dispatches a `CreateCollection` command that creates a `CollectionCreated` event.
  The event is then projected to the collections read model.

  ## Parameters

  - `title` - Collection title (required)
  - `slug` - URL-friendly identifier (required, must be unique per user)

  ## Example Request

      POST /api/v1/collections
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      Content-Type: application/json

      {
        "title": "Favorites",
        "slug": "favorites"
      }

  ## Example Response (Success)

      {
        "collection": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "user_id": "user-123",
          "title": "Favorites",
          "slug": "favorites",
          "feeds": [],
          "inserted_at": "2024-01-15T10:30:00Z",
          "updated_at": "2024-01-15T10:30:00Z"
        }
      }

  ## Example Response (Error)

      {
        "error": "slug_already_exists"
      }
  """
  def create(conn, %{"title" => title} = params) do
    user_id = conn.assigns.current_user_id
    is_default = Map.get(params, "is_default", false)

    command = %CreateCollection{
      user_id: user_id,
      title: title,
      is_default: is_default,
      event_infos: %{}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        # Query the created collection from projections
        # Note: we need to query by user_id and title since we just dispatched
        collection =
          ProjectionsRepo.get_by(Collection, user_id: user_id, title: title, deleted_at: nil) ||
          ProjectionsRepo.one(
            from(c in Collection,
              where: c.user_id == ^user_id and c.deleted_at is nil,
              order_by: [desc: :inserted_at],
              limit: 1
            )
          )

        if collection do
          conn
          |> put_status(:created)
          |> json(%{
            collection: format_collection(collection)
          })
        else
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "collection_creation_failed"})
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  Updates a collection.

  Dispatches an `UpdateCollection` command that creates a `CollectionUpdated` event.
  Currently only supports updating the collection title.

  ## Parameters

  - `id` - Collection ID (from URL)
  - `title` - New title (required)

  ## Example Request

      PATCH /api/v1/collections/550e8400-e29b-41d4-a716-446655440000
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      Content-Type: application/json

      {
        "title": "My Favorites"
      }

  ## Example Response (Success)

      {
        "collection": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "title": "My Favorites",
          "slug": "favorites",
          ...
        }
      }

  ## Example Response (Error)

      {
        "error": "not_found"
      }
  """
  def update(conn, %{"id" => collection_id} = params) do
    user_id = conn.assigns.current_user_id

    case ProjectionsRepo.get(Collection, collection_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      collection ->
        if collection.user_id == user_id && is_nil(collection.deleted_at) do
          title = Map.get(params, "title", collection.title)

          command = %UpdateCollection{
            user_id: user_id,
            collection_id: collection_id,
            title: title,
            event_infos: %{}
          }

          case Dispatcher.dispatch(command) do
            :ok ->
              updated_collection = ProjectionsRepo.get(Collection, collection_id)
              json(conn, %{collection: format_collection(updated_collection)})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: inspect(reason)})
          end
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
        end
    end
  end

  @doc """
  Deletes a collection.

  Performs a soft delete (marks deleted_at). The default collection (slug: "all")
  cannot be deleted.

  Dispatches a `DeleteCollection` command that creates a `CollectionDeleted` event.

  ## Parameters

  - `id` - Collection ID (from URL)

  ## Example Request

      DELETE /api/v1/collections/550e8400-e29b-41d4-a716-446655440000
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response (Success)

      {
        "status": "success"
      }

  ## Example Response (Error: default collection)

      {
        "error": "cannot_delete_default_collection"
      }

  ## Example Response (Error: not found)

      {
        "error": "not_found"
      }
  """
  def delete(conn, %{"id" => collection_id}) do
    user_id = conn.assigns.current_user_id

    case ProjectionsRepo.get(Collection, collection_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      collection ->
        if collection.user_id == user_id && is_nil(collection.deleted_at) do
          if collection.is_default do
            conn
            |> put_status(:forbidden)
            |> json(%{error: "cannot_delete_default_collection"})
          else
            command = %DeleteCollection{
              user_id: user_id,
              collection_id: collection_id,
              event_infos: %{}
            }

            case Dispatcher.dispatch(command) do
              :ok ->
                json(conn, %{status: "success"})

              {:error, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: inspect(reason)})
            end
          end
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
        end
    end
  end

  @doc """
  Adds a feed to a collection.

  Dispatches an `AddFeedToCollection` command that creates a `FeedAddedToCollection` event.

  The feed must already be subscribed by the user to be added to a collection.

  ## Parameters

  - `id` - Collection ID (from URL)
  - `rss_source_feed` - Base64-encoded feed URL (in body)

  ## Example Request

      POST /api/v1/collections/550e8400-e29b-41d4-a716-446655440000/feeds
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      Content-Type: application/json

      {
        "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9uZXdz"
      }

  ## Example Response (Success)

      {
        "status": "success"
      }

  ## Example Response (Error: feed not subscribed)

      {
        "error": "feed_not_subscribed"
      }

  ## Example Response (Error: already in collection)

      {
        "error": "feed_already_in_collection"
      }
  """
  def add_feed(conn, %{"id" => collection_id, "rss_source_feed" => feed}) do
    user_id = conn.assigns.current_user_id

    case ProjectionsRepo.get(Collection, collection_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      collection ->
        if collection.user_id == user_id && is_nil(collection.deleted_at) do
          # Verify user is subscribed to this feed
          subscription =
            ProjectionsRepo.get_by(Subscription,
              user_id: user_id,
              rss_source_feed: feed
            )

          if subscription do
            command = %AddFeedToCollection{
              user_id: user_id,
              collection_id: collection_id,
              rss_source_feed: feed,
              event_infos: %{}
            }

            case Dispatcher.dispatch(command) do
              :ok ->
                json(conn, %{status: "success"})

              {:error, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: inspect(reason)})
            end
          else
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "feed_not_subscribed"})
          end
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
        end
    end
  end

  @doc """
  Removes a feed from a collection.

  Dispatches a `RemoveFeedFromCollection` command that creates a `FeedRemovedFromCollection` event.

  ## Parameters

  - `id` - Collection ID (from URL)
  - `feed_id` - Base64-encoded feed URL (from URL)

  ## Example Request

      DELETE /api/v1/collections/550e8400-e29b-41d4-a716-446655440000/feeds/aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9uZXdz
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response (Success)

      {
        "status": "success"
      }

  ## Example Response (Error: feed not in collection)

      {
        "error": "feed_not_in_collection"
      }
  """
  def remove_feed(conn, %{"id" => collection_id, "feed_id" => feed}) do
    user_id = conn.assigns.current_user_id

    case ProjectionsRepo.get(Collection, collection_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      collection ->
        if collection.user_id == user_id && is_nil(collection.deleted_at) do
          command = %RemoveFeedFromCollection{
            user_id: user_id,
            collection_id: collection_id,
            rss_source_feed: feed,
            event_infos: %{}
          }

          case Dispatcher.dispatch(command) do
            :ok ->
              json(conn, %{status: "success"})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: inspect(reason)})
          end
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
        end
    end
  end

  # Private helpers

  @doc false
  defp format_collection(collection) do
    feeds =
      Enum.map(collection.collection_subscriptions || [], fn cs ->
        %{
          id: cs.id,
          rss_source_feed: cs.subscription.rss_source_feed,
          rss_feed_title: cs.subscription.rss_feed_title,
          subscribed_at: cs.subscription.subscribed_at
        }
      end)

    %{
      id: collection.id,
      user_id: collection.user_id,
      title: collection.title,
      is_default: collection.is_default,
      feeds: feeds,
      inserted_at: collection.inserted_at,
      updated_at: collection.updated_at
    }
  end
end
