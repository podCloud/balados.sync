defmodule BaladosSyncCore.Commands.UnlikePodcast do
  @moduledoc """
  Command to unlike a podcast feed.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          rss_source_feed: String.t(),
          unliked_at: DateTime.t() | nil,
          event_infos: map()
        }

  defstruct [
    :user_id,
    :rss_source_feed,
    :unliked_at,
    :event_infos
  ]
end
