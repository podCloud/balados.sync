defmodule BaladosSyncCore.Commands.RecordPlay do
  @moduledoc """
  Command to record a play event for an episode.

  This command records both the playback position and the played (completed) status
  for an episode. It's typically dispatched when the user plays an episode or marks
  it as completed. Results in a `PlayRecorded` event.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_item` - Base64-encoded episode identifier (format: "guid,enclosure_url")
  - `position` - Current playback position in seconds (integer)
  - `played` - Whether the episode has been completed (boolean)
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %RecordPlay{
        user_id: "user-123",
        rss_source_feed: "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        rss_source_item: "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
        position: 1234,
        played: false,
        event_infos: %{device_id: "device-456", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t(),
          rss_source_item: String.t(),
          position: integer(),
          played: boolean(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :position,
    :played,
    :event_infos
  ]
end
