defmodule BaladosSyncCore.Commands.SyncUserData do
  defstruct [
    :user_id,
    :device_id,
    :device_name,
    :subscriptions,
    :play_statuses,
    :playlists
  ]
end
