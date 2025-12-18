defmodule BaladosSyncCore.Dispatcher do
  @moduledoc """
  Main Commanded application for dispatching commands.

  The event store adapter is configured via application config:
  - Dev/Prod: Uses PostgreSQL EventStore adapter
  - Test: Uses In-Memory adapter for isolation
  """
  use Commanded.Application, otp_app: :balados_sync_core

  router(BaladosSyncCore.Dispatcher.Router)
end
