defmodule BaladosSyncCore.Commands.SyncUserData do
  defstruct [
    :user_id,
    :subscriptions,
    :play_statuses,
    :playlists,
    :event_infos
  ]
end
