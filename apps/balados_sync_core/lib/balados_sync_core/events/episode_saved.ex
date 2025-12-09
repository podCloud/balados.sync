defmodule BaladosSyncCore.Events.EpisodeSaved do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist,
    :rss_source_feed,
    :rss_source_item,
    :item_title,
    :feed_title,
    :timestamp,
    :event_infos
  ]
end
