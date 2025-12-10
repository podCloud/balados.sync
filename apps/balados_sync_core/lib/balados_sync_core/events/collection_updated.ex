defmodule BaladosSyncCore.Events.CollectionUpdated do
  @moduledoc """
  Emitted when a collection's properties are updated.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :title,
    :timestamp,
    :event_infos
  ]
end
