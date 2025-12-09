defmodule BaladosSyncCore.Commands.UpdatePlaylist do
  @moduledoc """
  Command to update playlist metadata.

  This command is dispatched when a user wants to update the information of an existing playlist
  (e.g., change its name or description).
  It results in a `PlaylistUpdated` event being persisted to the event store.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `playlist_slug` - URL-friendly slug for the playlist (e.g., "my-favorites")
  - `name` - New name for the playlist (optional, only update if provided)
  - `description` - New description for the playlist (optional, only update if provided)
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %UpdatePlaylist{
        user_id: "user-123",
        playlist_slug: "my-favorites",
        name: "Updated Playlist Name",
        description: "Updated description",
        event_infos: %{device_id: "device-000", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          playlist: String.t(),
          name: String.t() | nil,
          description: String.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :playlist,
    :name,
    :description,
    :event_infos
  ]
end
