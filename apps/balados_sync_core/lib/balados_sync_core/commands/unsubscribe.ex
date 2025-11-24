defmodule BaladosSyncCore.Commands.Unsubscribe do
  @moduledoc """
  Command to unsubscribe a user from a podcast feed.

  This command is dispatched when a user wants to remove a podcast from their subscriptions.
  It results in a `UserUnsubscribed` event being persisted to the event store.

  Note: The subscription is not deleted, only marked as unsubscribed. This preserves
  the subscription history in the event stream.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_id` - Unique identifier for the podcast (optional, looked up if not provided)
  - `unsubscribed_at` - DateTime when unsubscription occurred (defaults to now if not provided)
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %Unsubscribe{
        user_id: "user-123",
        rss_source_feed: "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        rss_source_id: "podcast-abc",
        unsubscribed_at: ~U[2024-01-20 14:00:00Z],
        event_infos: %{device_id: "device-456", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t(),
          rss_source_id: String.t() | nil,
          unsubscribed_at: DateTime.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :unsubscribed_at,
    :event_infos
  ]
end
