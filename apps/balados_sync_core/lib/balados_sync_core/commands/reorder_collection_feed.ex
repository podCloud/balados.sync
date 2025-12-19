defmodule BaladosSyncCore.Commands.ReorderCollectionFeed do
  @moduledoc """
  Command to reorder a feed within a collection.

  This command changes the position of a feed in a collection's ordered list.
  The new_position is the target index (0-based) where the feed should be moved.
  """

  @derive Jason.Encoder
  defstruct [
    :user_id,
    :collection_id,
    :rss_source_feed,
    :new_position,
    :event_infos
  ]
end
