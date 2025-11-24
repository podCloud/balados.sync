defmodule BaladosSyncCore.Commands.Subscribe do
  @moduledoc """
  Command to subscribe a user to a podcast feed.

  This command is dispatched when a user wants to add a podcast to their subscriptions.
  It results in a `UserSubscribed` event being persisted to the event store.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_id` - Unique identifier for the podcast (from feed metadata)
  - `subscribed_at` - DateTime when subscription occurred (defaults to now if not provided)
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %Subscribe{
        user_id: "user-123",
        rss_source_feed: "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        rss_source_id: "podcast-abc",
        subscribed_at: ~U[2024-01-15 10:30:00Z],
        event_infos: %{device_id: "device-456", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t(),
          rss_source_id: String.t(),
          subscribed_at: DateTime.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :subscribed_at,
    :event_infos
  ]
end
