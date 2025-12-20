defmodule BaladosSyncCore.Commands.ChangePlaylistVisibility do
  @moduledoc """
  Command to change the public visibility of a playlist.

  This command is dispatched when a user wants to make their playlist
  publicly visible or private.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `playlist_id` - UUID of the playlist to update
  - `is_public` - Whether the playlist should be publicly visible
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %ChangePlaylistVisibility{
        user_id: "user-123",
        playlist_id: "playlist-456",
        is_public: true,
        event_infos: %{device_id: "device-000", device_name: "Web Browser"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          playlist_id: String.t(),
          is_public: boolean(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :playlist_id,
    :is_public,
    :event_infos
  ]
end
