defmodule BaladosSyncCore.Commands.ChangeCollectionVisibility do
  @moduledoc """
  Command to change the public visibility of a collection.

  This command is dispatched when a user wants to make their collection
  publicly visible or private.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `collection_id` - UUID of the collection to update
  - `is_public` - Whether the collection should be publicly visible
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %ChangeCollectionVisibility{
        user_id: "user-123",
        collection_id: "collection-456",
        is_public: true,
        event_infos: %{device_id: "device-000", device_name: "Web Browser"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          collection_id: String.t(),
          is_public: boolean(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :collection_id,
    :is_public,
    :event_infos
  ]
end
