defmodule BaladosSyncCore.Commands.Subscribe do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :subscribed_at,
    :event_infos
  ]
end
