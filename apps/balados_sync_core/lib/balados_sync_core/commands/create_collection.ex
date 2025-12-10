defmodule BaladosSyncCore.Commands.CreateCollection do
  @moduledoc """
  Creates a new collection for organizing subscriptions.

  Collections allow users to group podcast feeds together.
  The default collection uses slug "all".
  """

  @type t :: %__MODULE__{
    user_id: String.t(),
    title: String.t(),
    slug: String.t(),
    event_infos: map()
  }

  defstruct [
    :user_id,
    :title,
    :slug,
    event_infos: %{}
  ]
end
