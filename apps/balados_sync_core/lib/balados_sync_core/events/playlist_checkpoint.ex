defmodule BaladosSyncCore.Events.PlaylistCheckpoint do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlists,
    :timestamp
  ]
end
