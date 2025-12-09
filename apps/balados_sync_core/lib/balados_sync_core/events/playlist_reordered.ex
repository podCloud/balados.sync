defmodule BaladosSyncCore.Events.PlaylistReordered do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist,
    :items,
    :timestamp,
    :event_infos
  ]
end
