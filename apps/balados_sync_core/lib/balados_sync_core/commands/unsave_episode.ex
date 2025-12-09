defmodule BaladosSyncCore.Commands.UnsaveEpisode do
  @moduledoc """
  Command to remove an episode from a playlist.

  This command is dispatched when a user wants to remove a saved episode from a playlist.
  It results in an `EpisodeUnsaved` event being persisted to the event store.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `playlist_id` - Unique identifier for the playlist
  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_item` - Unique identifier for the episode
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %UnsaveEpisode{
        user_id: "user-123",
        playlist_id: "playlist-456",
        rss_source_feed: "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        rss_source_item: "episode-789",
        event_infos: %{device_id: "device-000", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          playlist_id: String.t(),
          rss_source_feed: String.t(),
          rss_source_item: String.t(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :playlist_id,
    :rss_source_feed,
    :rss_source_item,
    :event_infos
  ]
end
