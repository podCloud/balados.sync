defmodule BaladosSyncCore.Commands.SaveEpisode do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :event_infos
  ]
end
