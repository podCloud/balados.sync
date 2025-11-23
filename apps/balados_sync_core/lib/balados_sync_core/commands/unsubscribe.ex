defmodule BaladosSyncCore.Commands.Unsubscribe do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :unsubscribed_at,
    :event_infos
  ]
end
