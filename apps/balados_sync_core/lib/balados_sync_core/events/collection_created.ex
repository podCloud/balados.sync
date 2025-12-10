defmodule BaladosSyncCore.Events.CollectionCreated do
  @moduledoc """
  Emitted when a new collection is created.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :title,
    :slug,
    :timestamp,
    :event_infos
  ]
end
