defmodule BaladosSyncCore.Events.UserUnsubscribed do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :unsubscribed_at,
    :timestamp,
    :event_infos
  ]
end
