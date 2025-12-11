defmodule BaladosSyncCore.Commands.DeleteCollection do
  @moduledoc """
  Deletes a collection.

  Default collections cannot be deleted - attempting to do so will fail.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          collection_id: String.t(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :collection_id,
    event_infos: %{}
  ]
end
