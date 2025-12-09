defmodule BaladosSyncCore.Commands.ReorderPlaylist do
  @moduledoc """
  Command to reorder episodes in a playlist.

  This command is dispatched when a user wants to change the order of episodes in a playlist.
  It results in a `PlaylistReordered` event being persisted to the event store.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `playlist_id` - Unique identifier for the playlist
  - `items` - List of items with new positions, each item is: `{rss_source_feed, rss_source_item, new_position}`
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %ReorderPlaylist{
        user_id: "user-123",
        playlist_id: "playlist-456",
        items: [
          {"feed1", "item1", 0},
          {"feed2", "item2", 1},
          {"feed3", "item3", 2}
        ],
        event_infos: %{device_id: "device-000", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          playlist_id: String.t(),
          items: list({String.t(), String.t(), integer()}),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :playlist_id,
    :items,
    :event_infos
  ]
end
