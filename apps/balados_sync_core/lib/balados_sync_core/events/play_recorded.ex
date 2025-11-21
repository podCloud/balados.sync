defmodule BaladosSyncCore.Events.PlayRecorded do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :position,
    :played,
    :timestamp,
    :event_infos
  ]
end
