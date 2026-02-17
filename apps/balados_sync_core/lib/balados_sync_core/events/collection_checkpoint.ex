defmodule BaladosSyncCore.Events.CollectionCheckpoint do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collections,
    :timestamp
  ]
end
