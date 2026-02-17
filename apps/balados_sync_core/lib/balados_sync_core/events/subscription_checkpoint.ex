defmodule BaladosSyncCore.Events.SubscriptionCheckpoint do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :subscriptions,
    :privacy,
    :timestamp
  ]
end
