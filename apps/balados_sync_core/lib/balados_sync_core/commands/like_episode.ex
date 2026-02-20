defmodule BaladosSyncCore.Commands.LikeEpisode do
  @moduledoc """
  Command to like an episode.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t(),
          rss_source_item: String.t(),
          liked_at: DateTime.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :liked_at,
    :event_infos
  ]
end
