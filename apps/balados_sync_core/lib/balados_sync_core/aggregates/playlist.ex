defmodule BaladosSyncCore.Aggregates.Playlist do
  @moduledoc """
  Playlist aggregate for the CQRS/Event Sourcing system.

  Handles creating, updating, deleting, and reordering playlists and their episodes.
  Split from the monolithic User aggregate as part of bounded context separation.

  ## State

  - `user_id` - Unique identifier for the user
  - `playlists` - Map of `%{playlist_id => %{name, description, type, items, is_public}}`
  """

  defstruct [
    :user_id,
    # %{playlist_id => %{name, description, type, items, is_public}}
    :playlists
  ]

  alias BaladosSyncCore.Commands.{
    CreatePlaylist,
    UpdatePlaylist,
    ReorderPlaylist,
    DeletePlaylist,
    ChangePlaylistVisibility,
    SaveEpisode,
    UnsaveEpisode,
    SnapshotPlaylist
  }

  alias BaladosSyncCore.Events.{
    PlaylistCreated,
    PlaylistUpdated,
    PlaylistReordered,
    PlaylistDeleted,
    PlaylistVisibilityChanged,
    EpisodeSaved,
    EpisodeUnsaved,
    PlaylistCheckpoint
  }

  # Valid playlist types
  @valid_playlist_types ["playlist", "queue"]

  # SnapshotPlaylist
  def execute(%__MODULE__{} = state, %SnapshotPlaylist{} = _cmd) do
    %PlaylistCheckpoint{
      user_id: state.user_id,
      playlists: state.playlists || %{},
      timestamp: DateTime.utc_now()
    }
  end

  # SaveEpisode
  def execute(%__MODULE__{user_id: nil}, %SaveEpisode{} = cmd) do
    %EpisodeSaved{
      user_id: cmd.user_id,
      playlist: cmd.playlist,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      item_title: cmd.item_title,
      feed_title: cmd.feed_title,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  def execute(%__MODULE__{} = _state, %SaveEpisode{} = cmd) do
    %EpisodeSaved{
      user_id: cmd.user_id,
      playlist: cmd.playlist,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      item_title: cmd.item_title,
      feed_title: cmd.feed_title,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # UnsaveEpisode
  def execute(%__MODULE__{user_id: nil}, %UnsaveEpisode{} = cmd) do
    %EpisodeUnsaved{
      user_id: cmd.user_id,
      playlist: cmd.playlist,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  def execute(%__MODULE__{} = _state, %UnsaveEpisode{} = cmd) do
    %EpisodeUnsaved{
      user_id: cmd.user_id,
      playlist: cmd.playlist,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # CreatePlaylist
  def execute(%__MODULE__{user_id: nil}, %CreatePlaylist{} = cmd) do
    do_create_playlist(%{}, cmd)
  end

  def execute(%__MODULE__{} = state, %CreatePlaylist{} = cmd) do
    do_create_playlist(state.playlists || %{}, cmd)
  end

  # DeletePlaylist
  def execute(%__MODULE__{} = state, %DeletePlaylist{} = cmd) do
    playlists = state.playlists || %{}

    if Map.has_key?(playlists, cmd.playlist_id) do
      %PlaylistDeleted{
        user_id: cmd.user_id,
        playlist_id: cmd.playlist_id,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        event_infos: cmd.event_infos || %{}
      }
    else
      {:error, :playlist_not_found}
    end
  end

  # UpdatePlaylist
  def execute(%__MODULE__{} = _state, %UpdatePlaylist{} = cmd) do
    %PlaylistUpdated{
      user_id: cmd.user_id,
      playlist: cmd.playlist,
      name: cmd.name,
      description: cmd.description,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ReorderPlaylist
  def execute(%__MODULE__{} = _state, %ReorderPlaylist{} = cmd) do
    %PlaylistReordered{
      user_id: cmd.user_id,
      playlist: cmd.playlist,
      items: cmd.items,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ChangePlaylistVisibility
  def execute(%__MODULE__{} = state, %ChangePlaylistVisibility{} = cmd) do
    playlists = state.playlists || %{}

    if Map.has_key?(playlists, cmd.playlist_id) do
      %PlaylistVisibilityChanged{
        user_id: cmd.user_id,
        playlist_id: cmd.playlist_id,
        is_public: cmd.is_public,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        event_infos: cmd.event_infos || %{}
      }
    else
      {:error, :playlist_not_found}
    end
  end

  # Private helpers

  defp do_create_playlist(playlists, cmd) do
    playlist_type = cmd.playlist_type || "playlist"

    cond do
      is_nil(cmd.name) || String.trim(cmd.name) == "" ->
        {:error, :name_required}

      playlist_type not in @valid_playlist_types ->
        {:error, :invalid_playlist_type}

      true ->
        playlist_id = cmd.playlist_id || Ecto.UUID.generate()

        if Map.has_key?(playlists, playlist_id) do
          {:error, :playlist_already_exists}
        else
          %PlaylistCreated{
            user_id: cmd.user_id,
            playlist_id: playlist_id,
            name: cmd.name,
            description: cmd.description,
            playlist_type: playlist_type,
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            event_infos: cmd.event_infos || %{}
          }
        end
    end
  end

  # Apply events
  def apply(%__MODULE__{} = state, %PlaylistCreated{} = event) do
    playlists = state.playlists || %{}

    new_playlist = %{
      name: event.name,
      description: event.description,
      type: event.playlist_type || "playlist",
      items: [],
      is_public: false
    }

    %{state | user_id: event.user_id, playlists: Map.put(playlists, event.playlist_id, new_playlist)}
  end

  def apply(%__MODULE__{} = state, %EpisodeSaved{} = event) do
    playlists = state.playlists || %{}

    playlist =
      Map.get(playlists, event.playlist, %{
        name: event.playlist,
        items: []
      })

    items = playlist.items || []
    new_item = {event.rss_source_feed, event.rss_source_item}

    items =
      if Enum.any?(items, fn {feed, item} ->
           feed == event.rss_source_feed and item == event.rss_source_item
         end) do
        items
      else
        items ++ [new_item]
      end

    updated_playlist = %{playlist | items: items}
    %{state | user_id: event.user_id, playlists: Map.put(playlists, event.playlist, updated_playlist)}
  end

  def apply(%__MODULE__{} = state, %EpisodeUnsaved{} = event) do
    playlists = state.playlists || %{}

    case Map.get(playlists, event.playlist) do
      nil ->
        state

      playlist ->
        items = playlist.items || []

        new_items =
          Enum.filter(items, fn {feed, item} ->
            not (feed == event.rss_source_feed and item == event.rss_source_item)
          end)

        updated_playlist = %{playlist | items: new_items}
        %{state | playlists: Map.put(playlists, event.playlist, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = state, %PlaylistUpdated{} = event) do
    playlists = state.playlists || %{}

    case Map.get(playlists, event.playlist) do
      nil ->
        state

      playlist ->
        updated_playlist = playlist
        updated_playlist = if event.name, do: %{updated_playlist | name: event.name}, else: updated_playlist
        updated_playlist = if event.description, do: %{updated_playlist | description: event.description}, else: updated_playlist

        %{state | playlists: Map.put(playlists, event.playlist, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = state, %PlaylistReordered{} = event) do
    playlists = state.playlists || %{}

    case Map.get(playlists, event.playlist) do
      nil ->
        state

      playlist ->
        updated_playlist = %{playlist | items: event.items}
        %{state | playlists: Map.put(playlists, event.playlist, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = state, %PlaylistDeleted{} = event) do
    playlists = state.playlists || %{}
    %{state | playlists: Map.delete(playlists, event.playlist_id)}
  end

  def apply(%__MODULE__{} = state, %PlaylistVisibilityChanged{} = event) do
    playlists = state.playlists || %{}

    case Map.get(playlists, event.playlist_id) do
      nil ->
        state

      playlist ->
        updated_playlist = Map.put(playlist, :is_public, event.is_public)
        %{state | playlists: Map.put(playlists, event.playlist_id, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = state, %PlaylistCheckpoint{} = event) do
    %{state | user_id: event.user_id, playlists: event.playlists}
  end

  def apply(%__MODULE__{} = state, _event), do: state
end
