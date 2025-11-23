defmodule BaladosSyncCore.Commands.RecordPlay do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :position,
    :played,
    :event_infos
  ]
end
