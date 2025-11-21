defmodule BaladosSyncCore.Commands.Snapshot do
  defstruct [
    :user_id,
    # boolean pour déclencher la suppression des events > 31j
    :cleanup_old_events
  ]
end
