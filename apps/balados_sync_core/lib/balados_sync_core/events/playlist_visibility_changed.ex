defmodule BaladosSyncCore.Events.PlaylistVisibilityChanged do
  @moduledoc """
  Event emitted when a playlist's visibility is changed.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist_id,
    :is_public,
    :timestamp,
    :event_infos
  ]
end
