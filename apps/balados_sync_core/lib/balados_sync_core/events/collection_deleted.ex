defmodule BaladosSyncCore.Events.CollectionDeleted do
  @moduledoc """
  Emitted when a collection is deleted.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :timestamp,
    :event_infos
  ]
end
