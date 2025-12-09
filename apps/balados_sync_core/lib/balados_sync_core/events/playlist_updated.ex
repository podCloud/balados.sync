defmodule BaladosSyncCore.Events.PlaylistUpdated do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist,
    :name,
    :description,
    :timestamp,
    :event_infos
  ]
end
