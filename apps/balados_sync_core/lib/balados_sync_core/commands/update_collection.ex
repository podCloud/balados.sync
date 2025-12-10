defmodule BaladosSyncCore.Commands.UpdateCollection do
  @moduledoc """
  Updates a collection's properties.

  Currently supports updating the title.
  """

  @type t :: %__MODULE__{
    user_id: String.t(),
    collection_id: String.t(),
    title: String.t() | nil,
    description: String.t() | nil,
    color: String.t() | nil,
    event_infos: map()
  }

  defstruct [
    :user_id,
    :collection_id,
    :title,
    :description,
    :color,
    event_infos: %{}
  ]
end
