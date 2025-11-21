defmodule BaladosSyncCore.Events.PrivacyChanged do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    # nil pour privacy globale
    :rss_source_feed,
    # nil pour privacy feed entier
    :rss_source_item,
    # :public | :anonymous | :private
    :privacy,
    :timestamp,
    :event_infos
  ]
end
