defmodule BaladosSyncCore.Commands.CreateCollection do
  @moduledoc """
  Creates a new collection for organizing subscriptions.

  Collections allow users to group podcast feeds together.
  """

  @type t :: %__MODULE__{
    user_id: String.t(),
    title: String.t(),
    is_default: boolean(),
    event_infos: map()
  }

  defstruct [
    :user_id,
    :title,
    is_default: false,
    event_infos: %{}
  ]
end
