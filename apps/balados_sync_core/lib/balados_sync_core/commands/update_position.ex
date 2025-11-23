defmodule BaladosSyncCore.Commands.UpdatePosition do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :position,
    :event_infos
  ]
end
