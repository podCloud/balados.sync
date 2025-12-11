defmodule BaladosSyncCore.Commands.AddFeedToCollection do
  @moduledoc """
  Adds a podcast feed to a collection.

  The feed must already be subscribed by the user.
  """

  @type t :: %__MODULE__{
          user_id: String.t(),
          collection_id: String.t(),
          rss_source_feed: String.t(),
          event_infos: map()
        }

  defstruct [
    :user_id,
    :collection_id,
    :rss_source_feed,
    event_infos: %{}
  ]
end
