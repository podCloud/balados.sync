defmodule BaladosSyncCore.Commands.CreateCollection do
  @moduledoc """
  Creates a new collection for organizing subscriptions.

  Collections allow users to group podcast feeds together.
  The default collection uses slug "all".

  Optional fields:
  - `collection_id` - If provided, uses this ID instead of generating one.
                     Used for deterministic IDs (e.g., default collection).
  """

  @type t :: %__MODULE__{
    user_id: String.t(),
    title: String.t(),
    slug: String.t(),
    collection_id: String.t() | nil,
    event_infos: map()
  }

  defstruct [
    :user_id,
    :title,
    :slug,
    :collection_id,
    event_infos: %{}
  ]
end
