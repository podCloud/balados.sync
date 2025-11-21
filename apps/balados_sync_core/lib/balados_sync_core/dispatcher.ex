defmodule BaladosSyncCore.Dispatcher do
  use Commanded.Application,
    otp_app: :balados_sync_core,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: BaladosSyncCore.EventStore
    ]

  router(BaladosSyncCore.Dispatcher.Router)
end
