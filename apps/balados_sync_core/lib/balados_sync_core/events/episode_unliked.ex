defmodule BaladosSyncCore.Events.EpisodeUnliked do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :unliked_at,
    :timestamp,
    :event_infos
  ]
end
