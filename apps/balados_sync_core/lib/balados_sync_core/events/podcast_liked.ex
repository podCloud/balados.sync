defmodule BaladosSyncCore.Events.PodcastLiked do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :liked_at,
    :timestamp,
    :event_infos
  ]
end
