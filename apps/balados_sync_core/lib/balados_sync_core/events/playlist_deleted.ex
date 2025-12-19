defmodule BaladosSyncCore.Events.PlaylistDeleted do
  @moduledoc """
  Emitted when a playlist is deleted.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist_id,
    :timestamp,
    :event_infos
  ]
end
