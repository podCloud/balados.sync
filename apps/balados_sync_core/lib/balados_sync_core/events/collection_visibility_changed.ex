defmodule BaladosSyncCore.Events.CollectionVisibilityChanged do
  @moduledoc """
  Event emitted when a collection's visibility is changed.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :is_public,
    :timestamp,
    :event_infos
  ]
end
