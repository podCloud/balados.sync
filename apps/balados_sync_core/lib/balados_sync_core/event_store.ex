defmodule BaladosSyncCore.EventStore do
  use EventStore, otp_app: :balados_sync_core

  # Cette fonction sera appelée lors de l'init
  def init(config) do
    {:ok, config}
  end
end
