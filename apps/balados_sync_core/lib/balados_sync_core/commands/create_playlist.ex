defmodule BaladosSyncCore.Commands.CreatePlaylist do
  @moduledoc """
  Creates a new playlist for organizing saved episodes.

  Playlists allow users to group episodes together in ordered lists.

  Optional fields:
  - `playlist_id` - If provided, uses this ID instead of generating one from the name.
  - `description` - Optional description for the playlist.
  - `playlist_type` - Type of playlist: "playlist" (default) or "queue" (device playback queue).
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          name: String.t(),
          playlist_id: String.t() | nil,
          description: String.t() | nil,
          playlist_type: String.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :name,
    :playlist_id,
    :description,
    :playlist_type,
    event_infos: %{}
  ]
end
