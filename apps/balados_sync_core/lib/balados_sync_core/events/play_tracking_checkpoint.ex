defmodule BaladosSyncCore.Events.PlayTrackingCheckpoint do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :play_statuses,
    :timestamp
  ]
end
