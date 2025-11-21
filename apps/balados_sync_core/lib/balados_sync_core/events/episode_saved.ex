defmodule BaladosSyncCore.Events.EpisodeSaved do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :timestamp,
    :event_infos
  ]
end
