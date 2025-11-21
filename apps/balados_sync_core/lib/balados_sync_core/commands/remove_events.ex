defmodule BaladosSyncCore.Commands.RemoveEvents do
  defstruct [
    :user_id,
    :device_id,
    :device_name,
    :rss_source_feed,
    :rss_source_item
  ]
end
