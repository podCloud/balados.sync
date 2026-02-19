defmodule BaladosSyncCore.Commands.LikePodcast do
  @moduledoc """
  Command to like a podcast feed.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t(),
          liked_at: DateTime.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :liked_at,
    :event_infos
  ]
end
