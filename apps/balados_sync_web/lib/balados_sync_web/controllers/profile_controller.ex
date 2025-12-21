defmodule BaladosSyncWeb.ProfileController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncProjections.Schemas.User
  alias BaladosSyncProjections.Schemas.PublicEvent
  alias BaladosSyncProjections.Schemas.{Playlist, PlaylistItem, Collection, CollectionSubscription}
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncCore.RssCache
  alias BaladosSyncWeb.PlaylistEnricher

  import Ecto.Query

  @doc """
  Shows the profile settings edit page for the current user.
  """
  def edit(conn, _params) do
    user = conn.assigns.current_user
    changeset = User.profile_changeset(user, %{})
    render(conn, :edit, user: user, changeset: changeset)
  end

  @doc """
  Updates the current user's profile settings.
  """
  def update(conn, %{"user" => profile_params}) do
    user = conn.assigns.current_user

    changeset = User.profile_changeset(user, profile_params)

    case SystemRepo.update(changeset) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, "Profile updated successfully.")
        |> redirect(to: ~p"/settings/profile")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, user: user, changeset: changeset)
    end
  end

  @doc """
  Shows a user's public profile page.

  Returns 404 if:
  - User doesn't exist
  - User's public profile is disabled
  """
  def show(conn, %{"username" => username}) do
    case get_public_user(username) do
      {:ok, user} ->
        # Get user's public timeline
        timeline = get_user_timeline(user.id)
        # Get user's public playlists and collections
        playlists = get_user_public_playlists(user.id)
        collections = get_user_public_collections(user.id)
        render(conn, :show, user: user, timeline: timeline, playlists: playlists, collections: collections)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: BaladosSyncWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp get_public_user(username) do
    case SystemRepo.get_by(User, username: username) do
      nil ->
        {:error, :not_found}

      user ->
        if user.public_profile_enabled do
          {:ok, user}
        else
          {:error, :not_found}
        end
    end
  end

  defp get_user_public_playlists(user_id) do
    from(p in Playlist,
      where: p.user_id == ^user_id,
      where: p.is_public == true,
      where: is_nil(p.deleted_at),
      order_by: [desc: p.updated_at],
      limit: 10
    )
    |> ProjectionsRepo.all()
  end

  defp get_user_public_collections(user_id) do
    from(c in Collection,
      where: c.user_id == ^user_id,
      where: c.is_public == true,
      where: is_nil(c.deleted_at),
      order_by: [desc: c.updated_at],
      limit: 10
    )
    |> ProjectionsRepo.all()
  end

  defp get_user_timeline(user_id) do
    # Query public events for this user
    events =
      from(pe in PublicEvent,
        where: pe.user_id == ^user_id and pe.privacy == "public",
        order_by: [desc: pe.event_timestamp],
        limit: 20
      )
      |> ProjectionsRepo.all()

    # Get feed URLs for metadata enrichment
    feed_urls =
      events
      |> Enum.map(& &1.rss_source_feed)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    feed_metadata = build_feed_metadata_map(feed_urls)

    # Format events for display
    Enum.map(events, fn event ->
      metadata = Map.get(feed_metadata, event.rss_source_feed)

      %{
        type: String.to_atom(event.event_type),
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        timestamp: event.event_timestamp,
        feed_title: metadata && metadata["title"],
        feed_image: metadata && get_in(metadata, ["cover", "src"]),
        item_title: event.event_data && event.event_data["item_title"]
      }
    end)
  end

  defp build_feed_metadata_map(encoded_feeds) do
    Enum.reduce(encoded_feeds, %{}, fn encoded_feed, acc ->
      case Base.url_decode64(encoded_feed, padding: false) do
        {:ok, feed_url} ->
          case RssCache.get_feed_metadata(feed_url) do
            {:ok, metadata} -> Map.put(acc, encoded_feed, metadata)
            _ -> acc
          end

        :error ->
          acc
      end
    end)
  end

  @doc """
  Shows a user's public playlist.

  Returns 404 if:
  - User doesn't exist
  - User's public profile is disabled
  - Playlist doesn't exist or isn't public
  """
  def show_playlist(conn, %{"username" => username, "id" => playlist_id}) do
    with {:ok, user} <- get_public_user(username),
         {:ok, playlist} <- get_public_playlist(user.id, playlist_id) do
      # Preload and enrich items
      playlist = ProjectionsRepo.preload(playlist,
        items: from(i in PlaylistItem, where: is_nil(i.deleted_at), order_by: [asc: i.position])
      )
      enriched_items = PlaylistEnricher.enrich_items(playlist.items)

      render(conn, :show_playlist, user: user, playlist: playlist, enriched_items: enriched_items)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: BaladosSyncWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp get_public_playlist(user_id, playlist_id) do
    playlist =
      from(p in Playlist,
        where: p.id == ^playlist_id,
        where: p.user_id == ^user_id,
        where: p.is_public == true,
        where: is_nil(p.deleted_at)
      )
      |> ProjectionsRepo.one()

    case playlist do
      nil -> {:error, :not_found}
      playlist -> {:ok, playlist}
    end
  end

  @doc """
  Shows a user's public collection.

  Returns 404 if:
  - User doesn't exist
  - User's public profile is disabled
  - Collection doesn't exist or isn't public
  """
  def show_collection(conn, %{"username" => username, "id" => collection_id}) do
    with {:ok, user} <- get_public_user(username),
         {:ok, collection} <- get_public_collection(user.id, collection_id) do
      # Preload subscriptions with their feeds
      collection = ProjectionsRepo.preload(collection,
        collection_subscriptions: from(cs in CollectionSubscription, order_by: [asc: cs.position])
      )

      # Enrich with feed metadata
      feeds = enrich_collection_feeds(collection.collection_subscriptions)

      render(conn, :show_collection, user: user, collection: collection, feeds: feeds)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: BaladosSyncWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp get_public_collection(user_id, collection_id) do
    collection =
      from(c in Collection,
        where: c.id == ^collection_id,
        where: c.user_id == ^user_id,
        where: c.is_public == true,
        where: is_nil(c.deleted_at)
      )
      |> ProjectionsRepo.one()

    case collection do
      nil -> {:error, :not_found}
      collection -> {:ok, collection}
    end
  end

  defp enrich_collection_feeds(collection_subscriptions) do
    Enum.map(collection_subscriptions, fn cs ->
      metadata = get_feed_metadata(cs.rss_source_feed)

      %{
        rss_source_feed: cs.rss_source_feed,
        position: cs.position,
        title: metadata && metadata["title"],
        image: metadata && get_in(metadata, ["cover", "src"]),
        description: metadata && metadata["description"]
      }
    end)
  end

  defp get_feed_metadata(encoded_feed) do
    case Base.url_decode64(encoded_feed, padding: false) do
      {:ok, feed_url} ->
        case RssCache.get_feed_metadata(feed_url) do
          {:ok, metadata} -> metadata
          _ -> nil
        end

      :error ->
        nil
    end
  end
end
