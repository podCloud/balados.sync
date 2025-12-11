defmodule BaladosSyncWeb.WebCollectionsController do
  @moduledoc """
  Web interface for managing user collections.

  Provides HTML views for users to create, edit, and delete collections,
  as well as view merged episodes from all feeds in a collection.
  """

  use BaladosSyncWeb, :controller

  require Logger

  alias BaladosSyncCore.Dispatcher

  alias BaladosSyncCore.Commands.{
    CreateCollection,
    UpdateCollection,
    DeleteCollection,
    AddFeedToCollection,
    RemoveFeedFromCollection
  }

  alias BaladosSyncCore.RssCache
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.Collection
  alias BaladosSyncWeb.Queries
  import Ecto.Query

  plug :require_authenticated_user

  @doc """
  List all collections for the current user.
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    collections = get_user_collections(user_id)

    render(conn, :index, collections: collections)
  end

  @doc """
  Show form to create a new collection.
  """
  def new(conn, _params) do
    user_id = conn.assigns.current_user.id
    subscriptions = get_user_subscriptions_with_metadata(user_id)

    render(conn, :new, subscriptions: subscriptions, changeset: %{})
  end

  @doc """
  Create a new collection.
  """
  def create(conn, %{"collection" => collection_params}) do
    user_id = conn.assigns.current_user.id
    title = Map.get(collection_params, "title", "")
    description = Map.get(collection_params, "description")
    color = Map.get(collection_params, "color")
    selected_feeds = Map.get(collection_params, "feeds", [])

    command = %CreateCollection{
      user_id: user_id,
      title: title,
      is_default: false,
      description: description,
      color: color,
      event_infos: %{}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        # Find the newly created collection and add feeds
        collection = get_latest_collection(user_id, title)

        if collection do
          # Add selected feeds to the collection
          Enum.each(selected_feeds, fn feed ->
            add_feed_command = %AddFeedToCollection{
              user_id: user_id,
              collection_id: collection.id,
              rss_source_feed: feed,
              event_infos: %{}
            }

            Dispatcher.dispatch(add_feed_command)
          end)
        end

        conn
        |> put_flash(:info, "Collection \"#{title}\" created successfully")
        |> redirect(to: ~p"/subscriptions/collections")

      {:error, reason} ->
        subscriptions = get_user_subscriptions_with_metadata(user_id)

        conn
        |> put_flash(:error, "Failed to create collection: #{inspect(reason)}")
        |> render(:new, subscriptions: subscriptions, changeset: collection_params)
    end
  end

  @doc """
  Show a collection with merged episodes from all feeds.
  """
  def show(conn, %{"id" => collection_id}) do
    user_id = conn.assigns.current_user.id

    case get_collection_for_user(collection_id, user_id) do
      nil ->
        conn
        |> put_flash(:error, "Collection not found")
        |> redirect(to: ~p"/subscriptions/collections")

      collection ->
        # Get episodes from all feeds in the collection
        episodes = get_merged_episodes(collection)

        render(conn, :show, collection: collection, episodes: episodes)
    end
  end

  @doc """
  Show form to edit a collection (manage feeds).
  """
  def edit(conn, %{"id" => collection_id}) do
    user_id = conn.assigns.current_user.id

    case get_collection_for_user(collection_id, user_id) do
      nil ->
        conn
        |> put_flash(:error, "Collection not found")
        |> redirect(to: ~p"/subscriptions/collections")

      collection ->
        subscriptions = get_user_subscriptions_with_metadata(user_id)

        # Get feeds currently in the collection
        collection_feeds =
          collection.collection_subscriptions
          |> Enum.map(& &1.rss_source_feed)
          |> MapSet.new()

        render(conn, :edit,
          collection: collection,
          subscriptions: subscriptions,
          collection_feeds: collection_feeds
        )
    end
  end

  @doc """
  Update a collection (title, description, color, and feeds).
  """
  def update(conn, %{"id" => collection_id, "collection" => collection_params}) do
    user_id = conn.assigns.current_user.id

    case get_collection_for_user(collection_id, user_id) do
      nil ->
        conn
        |> put_flash(:error, "Collection not found")
        |> redirect(to: ~p"/subscriptions/collections")

      collection ->
        title = Map.get(collection_params, "title", collection.title)
        description = Map.get(collection_params, "description", collection.description)
        color = Map.get(collection_params, "color", collection.color)
        selected_feeds = Map.get(collection_params, "feeds", []) |> MapSet.new()

        # Update collection metadata
        update_command = %UpdateCollection{
          user_id: user_id,
          collection_id: collection_id,
          title: title,
          description: description,
          color: color,
          event_infos: %{}
        }

        case Dispatcher.dispatch(update_command) do
          :ok ->
            # Sync feeds: add new ones, remove old ones
            current_feeds =
              collection.collection_subscriptions
              |> Enum.map(& &1.rss_source_feed)
              |> MapSet.new()

            # Feeds to add
            feeds_to_add = MapSet.difference(selected_feeds, current_feeds)

            Enum.each(feeds_to_add, fn feed ->
              add_cmd = %AddFeedToCollection{
                user_id: user_id,
                collection_id: collection_id,
                rss_source_feed: feed,
                event_infos: %{}
              }

              Dispatcher.dispatch(add_cmd)
            end)

            # Feeds to remove
            feeds_to_remove = MapSet.difference(current_feeds, selected_feeds)

            Enum.each(feeds_to_remove, fn feed ->
              remove_cmd = %RemoveFeedFromCollection{
                user_id: user_id,
                collection_id: collection_id,
                rss_source_feed: feed,
                event_infos: %{}
              }

              Dispatcher.dispatch(remove_cmd)
            end)

            conn
            |> put_flash(:info, "Collection updated successfully")
            |> redirect(to: ~p"/subscriptions/collections/#{collection_id}")

          {:error, reason} ->
            subscriptions = get_user_subscriptions_with_metadata(user_id)
            collection_feeds = selected_feeds

            conn
            |> put_flash(:error, "Failed to update: #{inspect(reason)}")
            |> render(:edit,
              collection: collection,
              subscriptions: subscriptions,
              collection_feeds: collection_feeds
            )
        end
    end
  end

  @doc """
  Delete a collection (except default).
  """
  def delete(conn, %{"id" => collection_id}) do
    user_id = conn.assigns.current_user.id

    case get_collection_for_user(collection_id, user_id) do
      nil ->
        conn
        |> put_flash(:error, "Collection not found")
        |> redirect(to: ~p"/subscriptions/collections")

      collection ->
        if collection.is_default do
          conn
          |> put_flash(:error, "Cannot delete the default collection")
          |> redirect(to: ~p"/subscriptions/collections")
        else
          command = %DeleteCollection{
            user_id: user_id,
            collection_id: collection_id,
            event_infos: %{}
          }

          case Dispatcher.dispatch(command) do
            :ok ->
              conn
              |> put_flash(:info, "Collection \"#{collection.title}\" deleted")
              |> redirect(to: ~p"/subscriptions/collections")

            {:error, reason} ->
              conn
              |> put_flash(:error, "Failed to delete: #{inspect(reason)}")
              |> redirect(to: ~p"/subscriptions/collections")
          end
        end
    end
  end

  # ===== Private Helpers =====

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to manage collections")
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  defp get_user_collections(user_id) do
    from(c in Collection,
      where: c.user_id == ^user_id,
      where: is_nil(c.deleted_at),
      order_by: [desc: c.is_default, asc: c.title],
      preload: [collection_subscriptions: :subscription]
    )
    |> ProjectionsRepo.all()
  end

  defp get_collection_for_user(collection_id, user_id) do
    case ProjectionsRepo.get(Collection, collection_id) do
      nil ->
        nil

      collection ->
        if collection.user_id == user_id && is_nil(collection.deleted_at) do
          ProjectionsRepo.preload(collection, collection_subscriptions: :subscription)
        else
          nil
        end
    end
  end

  defp get_latest_collection(user_id, title) do
    from(c in Collection,
      where: c.user_id == ^user_id,
      where: c.title == ^title,
      where: is_nil(c.deleted_at),
      order_by: [desc: c.inserted_at],
      limit: 1
    )
    |> ProjectionsRepo.one()
  end

  defp get_user_subscriptions_with_metadata(user_id) do
    Queries.get_user_subscriptions(user_id)
    |> Enum.map(fn sub ->
      metadata = fetch_metadata_safe(sub.rss_source_feed)
      Map.put(sub, :metadata, metadata)
    end)
  end

  defp fetch_metadata_safe(encoded_feed) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      metadata
    else
      _ -> nil
    end
  end

  defp get_merged_episodes(collection) do
    # Get all feed URLs in this collection
    feed_urls =
      collection.collection_subscriptions
      |> Enum.map(& &1.rss_source_feed)

    # Fetch episodes from each feed and merge
    feed_urls
    |> Enum.flat_map(fn encoded_feed ->
      case fetch_feed_episodes(encoded_feed) do
        {:ok, episodes} ->
          Enum.map(episodes, fn ep ->
            Map.put(ep, :feed_encoded, encoded_feed)
          end)

        _ ->
          []
      end
    end)
    |> Enum.sort_by(& &1.pub_date, {:desc, DateTime})
    |> Enum.take(100)
  end

  defp fetch_feed_episodes(encoded_feed) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      episodes =
        (metadata.episodes || [])
        |> Enum.map(fn ep ->
          %{
            title: ep.title,
            description: ep.description,
            pub_date: parse_date(ep.pub_date),
            duration: ep.duration,
            enclosure: ep.enclosure,
            guid: ep.guid,
            feed_title: metadata.title,
            feed_cover: metadata.cover
          }
        end)

      {:ok, episodes}
    else
      _ -> {:error, :fetch_failed}
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_date(_), do: nil
end
