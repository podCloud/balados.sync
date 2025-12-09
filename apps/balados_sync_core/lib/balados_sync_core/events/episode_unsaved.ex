defmodule BaladosSyncCore.Events.EpisodeUnsaved do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :playlist,
    :rss_source_feed,
    :rss_source_item,
    :timestamp,
    :event_infos
  ]
end
