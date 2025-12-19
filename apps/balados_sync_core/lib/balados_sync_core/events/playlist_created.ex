defmodule BaladosSyncCore.Events.PlaylistCreated do
  @moduledoc """
  Emitted when a new playlist is explicitly created.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist_id,
    :name,
    :description,
    :timestamp,
    :event_infos
  ]
end
