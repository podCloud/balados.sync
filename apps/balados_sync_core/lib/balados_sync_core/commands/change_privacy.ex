defmodule BaladosSyncCore.Commands.ChangePrivacy do
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_item,
    :privacy,
    :event_infos
  ]
end
