defmodule BaladosSyncCore.Commands.DeletePlaylist do
  @moduledoc """
  Deletes a playlist.

  This command soft-deletes the playlist and all its items.
  The playlist cannot be recovered after deletion.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          playlist_id: String.t(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :playlist_id,
    event_infos: %{}
  ]
end
