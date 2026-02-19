defmodule BaladosSyncCore.Events.LikeCheckpoint do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :podcast_likes,
    :episode_likes,
    :timestamp
  ]
end
