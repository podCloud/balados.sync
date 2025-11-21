defmodule BaladosSyncCore.Commands.Unsubscribe do
  defstruct [
    :user_id,
    :device_id,
    :device_name,
    :rss_source_feed,
    :rss_source_id,
    :unsubscribed_at
  ]
end
