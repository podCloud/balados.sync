defmodule BaladosSyncCore.Commands.SaveEpisode do
  @moduledoc """
  Command to save an episode to a playlist.

  This command is dispatched when a user wants to save an episode to a playlist.
  If the playlist doesn't exist, it will be created implicitly with the provided name.
  It results in an `EpisodeSaved` event being persisted to the event store.

  ## Fields

  - `user_id` - Unique identifier for the user
  - `playlist_name` - Name of the playlist (slug generated from this: "My Favorites" -> "my-favorites")
  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_item` - Unique identifier for the episode
  - `item_title` - Title of the episode
  - `feed_title` - Title of the podcast feed
  - `event_infos` - Map containing device_id and device_name for audit trail

  ## Example

      %SaveEpisode{
        user_id: "user-123",
        playlist_name: "My Favorite Episodes",
        rss_source_feed: "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        rss_source_item: "episode-789",
        item_title: "Episode 42: The Answer",
        feed_title: "My Podcast",
        event_infos: %{device_id: "device-000", device_name: "iPhone"}
      }
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          playlist: String.t(),
          rss_source_feed: String.t(),
          rss_source_item: String.t(),
          item_title: String.t(),
          feed_title: String.t(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :playlist,
    :rss_source_feed,
    :rss_source_item,
    :item_title,
    :feed_title,
    :event_infos
  ]
end
