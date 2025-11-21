defmodule BaladosSyncCore.Events.PopularityRecalculated do
  @derive Jason.Encoder
  defstruct [
    :rss_source_feed,
    :rss_source_item,
    :plays,
    :likes,
    :timestamp
  ]
end
