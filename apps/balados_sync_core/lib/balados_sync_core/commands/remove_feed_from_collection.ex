defmodule BaladosSyncCore.Commands.RemoveFeedFromCollection do
  @moduledoc """
  Removes a podcast feed from a collection.

  The feed will be unlinked from the collection but the subscription remains.
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
