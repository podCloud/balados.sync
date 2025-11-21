defmodule BaladosSyncCore.Events.PositionUpdated do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :position,
    :timestamp,
    :event_infos
  ]
end
