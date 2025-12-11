defmodule BaladosSyncCore.Events.CollectionCreated do
  @moduledoc """
  Emitted when a new collection is created.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :title,
    :is_default,
    :description,
    :color,
    :timestamp,
    :event_infos
  ]
end
