defmodule BaladosSyncWeb.LiveWebSocket do
  @moduledoc """
  WebSocket handler for real-time play gateway communication.

  Implements the WebSock behaviour for standard WebSocket connections.
  Handles authentication via PlayToken or JWT, and dispatches play events.

  Connection flow:
  1. Client connects to /api/v1/live (not authenticated)
  2. Server sends welcome message
  3. Client sends {"type": "auth", "token": "..."} message
  4. Server validates token and transitions to authenticated state
  5. Client sends {"type": "record_play", ...} messages
  6. Server dispatches commands and sends responses
  """

  require Logger
  @behaviour WebSock

  alias BaladosSyncWeb.LiveWebSocket.{State, MessageHandler}

  @doc """
  Initializes the WebSocket connection.

  Creates an unauthenticated connection state and sends a welcome message.
  """
  @impl WebSock
  def init(_conn_params) do
    state = State.new()
    welcome_msg = welcome_message()
    Logger.info("New WebSocket connection from client")
    {:push, {:text, welcome_msg}, state}
  end

  @doc """
  Handles incoming messages.

  First checks rate limit, then parses JSON messages and delegates to
  MessageHandler for processing. Rejects binary messages (only JSON over text frames).
  """
  @impl WebSock
  def handle_in({message, opcode: :text}, state) do
    Logger.debug("Received text message: #{inspect(message)}")

    # Check rate limit first
    case State.check_rate_limit(state) do
      {:ok, rate_limited_state} ->
        # Rate limit OK, process message
        case MessageHandler.handle_message(message, rate_limited_state) do
          {:ok, response, new_state} ->
            {:push, {:text, response}, new_state}

          {:error, error_response} ->
            {:push, {:text, error_response}, rate_limited_state}
        end

      {:error, :rate_limited, rate_limited_state} ->
        # Rate limit exceeded
        Logger.warning("Rate limit exceeded for connection")
        error = error_response("Rate limit exceeded. Please slow down.", "RATE_LIMITED")
        {:push, {:text, error}, rate_limited_state}
    end
  rescue
    e ->
      Logger.error("Exception in handle_in: #{inspect(e)}")
      error = error_response("Internal server error", "INTERNAL_ERROR")
      {:push, {:text, error}, state}
  end

  @impl WebSock
  def handle_in({_data, opcode: :binary}, state) do
    Logger.debug("Rejected binary message")
    error = error_response("Binary messages not supported", "INVALID_FORMAT")
    {:push, {:text, error}, state}
  end

  @doc """
  Handles unexpected info messages.
  """
  @impl WebSock
  def handle_info(msg, state) do
    Logger.debug("Received unexpected info message: #{inspect(msg)}")
    {:ok, state}
  end

  @doc """
  Handles connection termination.

  Logs disconnection with user info if available.
  """
  @impl WebSock
  def terminate(reason, state) do
    if State.authenticated?(state) do
      Logger.info("WebSocket disconnected for user #{state.user_id} (reason: #{inspect(reason)})")
    else
      Logger.info("WebSocket disconnected (unauthenticated, reason: #{inspect(reason)})")
    end

    :ok
  end

  # Private functions

  defp welcome_message do
    Jason.encode!(%{
      "status" => "connected",
      "message" => "Balados Sync live connection ready. Send auth message to authenticate."
    })
  end

  defp error_response(message, code) do
    Jason.encode!(%{
      "status" => "error",
      "error" => %{
        "message" => message,
        "code" => code
      }
    })
  end
end
