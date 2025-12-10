defmodule BaladosSyncCore.Commands.UpdateCollection do
  @moduledoc """
  Updates a collection's properties.

  Currently supports updating the title.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          collection_id: String.t(),
          title: String.t(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :collection_id,
    :title,
    event_infos: %{}
  ]
end
