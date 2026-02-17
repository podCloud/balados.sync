defmodule BaladosSyncCore.Commands.SnapshotSubscription do
  defstruct [
    :user_id,
    :cleanup_old_events
  ]
end
