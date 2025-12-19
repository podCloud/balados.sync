defmodule BaladosSyncCore.Events.CollectionFeedReordered do
  @moduledoc """
  Emitted when a feed's position within a collection is changed.

  Contains the new ordered list of feeds for the collection to ensure
  consistent state reconstruction during event replay.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :rss_source_feed,
    :new_position,
    :feed_order,
    :timestamp,
    :event_infos
  ]
end
