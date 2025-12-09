defmodule BaladosSyncCore.Events.PlaylistReordered do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist_id,
    :items,
    :timestamp,
    :event_infos
  ]
end
