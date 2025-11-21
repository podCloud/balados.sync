defmodule BaladosSyncCore.Events.UserCheckpoint do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :subscriptions,
    :play_statuses,
    :playlists,
    :timestamp
  ]
end
