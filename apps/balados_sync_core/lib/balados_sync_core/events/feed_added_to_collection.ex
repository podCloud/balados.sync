defmodule BaladosSyncCore.Events.FeedAddedToCollection do
  @moduledoc """
  Emitted when a feed is added to a collection.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :rss_source_feed,
    :timestamp,
    :event_infos
  ]
end
