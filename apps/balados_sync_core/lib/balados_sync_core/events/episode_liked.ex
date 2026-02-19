defmodule BaladosSyncCore.Events.EpisodeLiked do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :liked_at,
    :timestamp,
    :event_infos
  ]
end
