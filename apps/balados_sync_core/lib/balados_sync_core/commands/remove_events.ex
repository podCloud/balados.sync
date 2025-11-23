defmodule BaladosSyncCore.Commands.RemoveEvents do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :event_infos
  ]
end
