defmodule BaladosSyncCore.Events.PodcastUnliked do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :unliked_at,
    :timestamp,
    :event_infos
  ]
end
