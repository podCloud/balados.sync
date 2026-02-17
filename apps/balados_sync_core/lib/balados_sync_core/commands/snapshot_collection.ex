defmodule BaladosSyncCore.Commands.SnapshotCollection do
  defstruct [
    :user_id,
    :cleanup_old_events
  ]
end
