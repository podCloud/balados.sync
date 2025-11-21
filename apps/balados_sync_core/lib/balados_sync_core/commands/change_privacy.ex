defmodule BaladosSyncCore.Commands.ChangePrivacy do
  defstruct [
    :user_id,
    :device_id,
    :device_name,
    :privacy
  ]
end
