defmodule BaladosSyncCore.Commands.CreatePlaylist do
  @moduledoc """
  Creates a new playlist for organizing saved episodes.

  Playlists allow users to group episodes together in ordered lists.

  Optional fields:
  - `playlist_id` - If provided, uses this ID instead of generating one from the name.
  - `description` - Optional description for the playlist.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          name: String.t(),
          playlist_id: String.t() | nil,
          description: String.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :name,
    :playlist_id,
    :description,
    event_infos: %{}
  ]
end
