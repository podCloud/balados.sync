defmodule BaladosSyncWeb.LiveWebSocket.State do
  @moduledoc """
  Connection state for the LiveWebSocket handler.

  Tracks authentication status, user identity, token information, and connection metadata.
  """

  @type auth_status :: :unauthenticated | :authenticated
  @type token_type :: :play_token | :jwt_token

  @type t :: %__MODULE__{
          auth_status: auth_status(),
          user_id: String.t() | nil,
          token_type: token_type() | nil,
          token_value: String.t() | nil,
          device_id: String.t(),
          device_name: String.t(),
          connected_at: DateTime.t(),
          last_activity_at: DateTime.t(),
          message_count: non_neg_integer()
        }

  defstruct [
    :user_id,
    :token_type,
    :token_value,
    :connected_at,
    :last_activity_at,
    auth_status: :unauthenticated,
    device_id: "websocket",
    device_name: "WebSocket Live",
    message_count: 0
  ]

  @doc """
  Creates a new connection state.

  The connection starts in the unauthenticated state, ready to receive an auth message.
  """
  @spec new() :: t()
  def new do
    now = DateTime.utc_now()

    %__MODULE__{
      auth_status: :unauthenticated,
      user_id: nil,
      token_type: nil,
      token_value: nil,
      device_id: "websocket",
      device_name: "WebSocket Live",
      connected_at: now,
      last_activity_at: now,
      message_count: 0
    }
  end

  @doc """
  Authenticates the connection with the given user and token information.

  Transitions from :unauthenticated to :authenticated state.

  Accepts optional device_id and device_name. If not provided, uses defaults
  ("websocket" and "WebSocket Live").
  """
  @spec authenticate(t(), String.t(), token_type(), String.t(), keyword()) :: t()
  def authenticate(%__MODULE__{} = state, user_id, token_type, token_value, opts \\ []) do
    device_id = Keyword.get(opts, :device_id, "websocket")
    device_name = Keyword.get(opts, :device_name, "WebSocket Live")

    %__MODULE__{
      state
      | auth_status: :authenticated,
        user_id: user_id,
        token_type: token_type,
        token_value: token_value,
        device_id: device_id,
        device_name: device_name,
        last_activity_at: DateTime.utc_now()
    }
  end

  @doc """
  Updates the last activity timestamp and increments message count.
  """
  @spec touch(t()) :: t()
  def touch(%__MODULE__{} = state) do
    %__MODULE__{
      state
      | last_activity_at: DateTime.utc_now(),
        message_count: state.message_count + 1
    }
  end

  @doc """
  Checks if the connection is authenticated.
  """
  @spec authenticated?(t()) :: boolean()
  def authenticated?(%__MODULE__{} = state) do
    state.auth_status == :authenticated
  end
end
