defmodule BaladosSyncCore.Events.UserSubscribed do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :subscribed_at,
    :timestamp,
    # %{device_id: ..., device_name: ...}
    :event_infos
  ]
end
