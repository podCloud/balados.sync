defmodule BaladosSyncCore.Commands.UpdatePosition do
  @moduledoc """
  Command to update only the playback position for an episode.

  This command updates the playback position without changing the played status.
  It's useful for periodic position saves during playback. Results in a
  `PositionUpdated` event.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `rss_source_feed` - Base64-encoded RSS feed URL (optional, looked up if not provided)
  - `rss_source_item` - Base64-encoded episode identifier (format: "guid,enclosure_url")
  - `position` - Current playback position in seconds (integer)
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %UpdatePosition{
        user_id: "user-123",
        rss_source_feed: "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        rss_source_item: "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
        position: 1567,
        event_infos: %{device_id: "device-456", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t() | nil,
          rss_source_item: String.t(),
          position: integer(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :position,
    :event_infos
  ]
end
