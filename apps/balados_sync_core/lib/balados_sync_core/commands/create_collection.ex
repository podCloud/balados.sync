defmodule BaladosSyncCore.Commands.CreateCollection do
  @moduledoc """
  Creates a new collection for organizing subscriptions.

  Collections allow users to group podcast feeds together.
  The default collection (is_default: true) automatically includes all new subscriptions.

  Optional fields:
  - `collection_id` - If provided, uses this ID instead of generating one.
  - `is_default` - If true, marks this as the default collection (default: false).
  """

  @type t :: %__MODULE__{
    user_id: String.t(),
    title: String.t(),
    is_default: boolean(),
    collection_id: String.t() | nil,
    description: String.t() | nil,
    color: String.t() | nil,
    event_infos: map()
  }

  defstruct [
    :user_id,
    :title,
    :collection_id,
    :description,
    :color,
    is_default: false,
    event_infos: %{}
  ]
end
