defmodule BaladosSyncWeb.PlaylistsController do
  @moduledoc """
  Web controller for managing user playlists.

  Provides HTML interface for playlist CRUD operations.
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher

  alias BaladosSyncCore.Commands.{
    CreatePlaylist,
    UpdatePlaylist,
    DeletePlaylist,
    ChangePlaylistVisibility
  }

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Playlist, PlaylistItem}
  alias BaladosSyncWeb.PlaylistEnricher
  import Ecto.Query

  plug :require_authenticated_user

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, gettext("auth.must_log_in"))
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  # Private helpers for DRY playlist queries

  @doc false
  defp get_user_playlist(user_id, playlist_id) do
    from(p in Playlist,
      where: p.id == ^playlist_id,
      where: p.user_id == ^user_id,
      where: is_nil(p.deleted_at)
    )
    |> ProjectionsRepo.one()
  end

  @doc false
  defp preload_playlist_items(nil), do: nil

  defp preload_playlist_items(playlist) do
    ProjectionsRepo.preload(playlist,
      items: from(i in PlaylistItem, where: is_nil(i.deleted_at), order_by: [asc: i.position])
    )
  end

  @doc """
  Lists all playlists for the current user.
  Uses a subquery to count items efficiently (avoids N+1 queries).

  Note: This endpoint only shows regular playlists (type="playlist").
  Device playback queues (type="queue") are excluded from the Web UI
  and are only accessible via the Sync API. See docs/FEATURES.md for details.
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id

    # Subquery to count active items per playlist
    items_count_subquery =
      from(i in PlaylistItem,
        where: i.playlist_id == parent_as(:playlist).id,
        where: is_nil(i.deleted_at),
        select: count(i.id)
      )

    playlists =
      from(p in Playlist,
        as: :playlist,
        where: p.user_id == ^user_id,
        where: is_nil(p.deleted_at),
        # Filter to show only regular playlists in Web UI.
        # Queues (type="queue") are device-specific and sync-only.
        where: coalesce(p.type, "playlist") == "playlist",
        order_by: [desc: p.updated_at],
        select_merge: %{items_count: subquery(items_count_subquery)}
      )
      |> ProjectionsRepo.all()

    render(conn, :index, playlists: playlists)
  end

  @doc """
  Shows form to create a new playlist.
  """
  def new(conn, _params) do
    render(conn, :new)
  end

  @doc """
  Creates a new playlist.
  """
  def create(conn, %{"playlist" => playlist_params}) do
    user_id = conn.assigns.current_user.id
    name = playlist_params["name"]
    description = playlist_params["description"]

    command = %CreatePlaylist{
      user_id: user_id,
      name: name,
      description: description,
      event_infos: %{}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        conn
        |> put_flash(:info, gettext("playlists.created_success"))
        |> redirect(to: ~p"/playlists")

      {:error, :name_required} ->
        conn
        |> put_flash(:error, gettext("playlists.name_required"))
        |> render(:new)

      {:error, :playlist_already_exists} ->
        conn
        |> put_flash(:error, gettext("playlists.name_taken"))
        |> render(:new)

      {:error, :invalid_playlist_type} ->
        conn
        |> put_flash(:error, gettext("playlists.invalid_type"))
        |> render(:new)

      {:error, reason} ->
        conn
        |> put_flash(:error, gettext("playlists.create_error") <> ": #{inspect(reason)}")
        |> render(:new)
    end
  end

  @doc """
  Shows a playlist with its episodes.

  Fetches RSS feeds in parallel to enrich episode metadata with:
  - Full descriptions
  - Cover images
  - Publication dates
  - Duration
  - Enclosure (audio file) info
  """
  def show(conn, %{"id" => playlist_id}) do
    user_id = conn.assigns.current_user.id

    playlist =
      user_id
      |> get_user_playlist(playlist_id)
      |> preload_playlist_items()

    if playlist do
      # Enrich items with metadata from RSS feeds
      enriched_items = PlaylistEnricher.enrich_items(playlist.items)

      render(conn, :show, playlist: playlist, enriched_items: enriched_items)
    else
      conn
      |> put_flash(:error, gettext("playlists.not_found"))
      |> redirect(to: ~p"/playlists")
    end
  end

  @doc """
  Shows form to edit a playlist.
  """
  def edit(conn, %{"id" => playlist_id}) do
    user_id = conn.assigns.current_user.id
    playlist = get_user_playlist(user_id, playlist_id)

    if playlist do
      render(conn, :edit, playlist: playlist)
    else
      conn
      |> put_flash(:error, gettext("playlists.not_found"))
      |> redirect(to: ~p"/playlists")
    end
  end

  @doc """
  Updates a playlist.
  """
  def update(conn, %{"id" => playlist_id, "playlist" => playlist_params}) do
    user_id = conn.assigns.current_user.id
    playlist = get_user_playlist(user_id, playlist_id)

    if playlist do
      command = %UpdatePlaylist{
        user_id: user_id,
        playlist: playlist_id,
        name: playlist_params["name"],
        description: playlist_params["description"],
        event_infos: %{}
      }

      case Dispatcher.dispatch(command) do
        :ok ->
          conn
          |> put_flash(:info, gettext("playlists.updated_success"))
          |> redirect(to: ~p"/playlists/#{playlist_id}")

        {:error, reason} ->
          conn
          |> put_flash(:error, gettext("playlists.update_error") <> ": #{inspect(reason)}")
          |> render(:edit, playlist: playlist)
      end
    else
      conn
      |> put_flash(:error, gettext("playlists.not_found"))
      |> redirect(to: ~p"/playlists")
    end
  end

  @doc """
  Deletes a playlist.
  """
  def delete(conn, %{"id" => playlist_id}) do
    user_id = conn.assigns.current_user.id

    command = %DeletePlaylist{
      user_id: user_id,
      playlist_id: playlist_id,
      event_infos: %{}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        conn
        |> put_flash(:info, gettext("playlists.deleted_success"))
        |> redirect(to: ~p"/playlists")

      {:error, :playlist_not_found} ->
        conn
        |> put_flash(:error, gettext("playlists.not_found"))
        |> redirect(to: ~p"/playlists")

      {:error, reason} ->
        conn
        |> put_flash(:error, gettext("playlists.delete_error") <> ": #{inspect(reason)}")
        |> redirect(to: ~p"/playlists")
    end
  end

  @doc """
  Toggles the public visibility of a playlist.
  """
  def toggle_visibility(conn, %{"id" => playlist_id}) do
    user_id = conn.assigns.current_user.id
    playlist = get_user_playlist(user_id, playlist_id)

    if playlist do
      # Toggle the visibility
      new_visibility = not (playlist.is_public || false)

      command = %ChangePlaylistVisibility{
        user_id: user_id,
        playlist_id: playlist_id,
        is_public: new_visibility,
        event_infos: %{device_id: "web", device_name: "Web Browser"}
      }

      case Dispatcher.dispatch(command) do
        :ok ->
          visibility_text = if new_visibility, do: "public", else: "private"

          conn
          |> put_flash(:info, gettext("playlists.visibility_changed") <> " #{visibility_text}.")
          |> redirect(to: ~p"/playlists/#{playlist_id}")

        {:error, reason} ->
          conn
          |> put_flash(:error, gettext("playlists.visibility_error") <> ": #{inspect(reason)}")
          |> redirect(to: ~p"/playlists/#{playlist_id}")
      end
    else
      conn
      |> put_flash(:error, gettext("playlists.not_found"))
      |> redirect(to: ~p"/playlists")
    end
  end
end
