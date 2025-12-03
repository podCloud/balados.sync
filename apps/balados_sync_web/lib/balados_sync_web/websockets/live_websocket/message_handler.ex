defmodule BaladosSyncWeb.LiveWebSocket.MessageHandler do
  @moduledoc """
  Message handler for the LiveWebSocket.

  Parses and validates incoming JSON messages, authenticates if needed, and dispatches commands.
  """

  require Logger
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.RecordPlay
  alias BaladosSyncWeb.LiveWebSocket.{Auth, State}

  @doc """
  Handles an incoming message from the WebSocket client.

  If not authenticated, only accepts {"type": "auth", "token": "..."} messages.
  If authenticated, processes record_play and other message types.

  Returns {:ok, response_json, new_state} or {:error, error_json}
  """
  @spec handle_message(String.t(), State.t()) ::
    {:ok, String.t(), State.t()} | {:error, String.t()}
  def handle_message(json_string, %State{} = state) do
    case parse_json(json_string) do
      {:ok, message} ->
        handle_parsed_message(message, state)

      {:error, reason} ->
        Logger.warning("Failed to parse JSON: #{inspect(reason)}")
        {:error, error_response("Invalid JSON format", "INVALID_JSON")}
    end
  end

  # Private functions

  @doc false
  defp parse_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, message} -> {:ok, message}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc false
  defp handle_parsed_message(%{"type" => "auth", "token" => token}, state) do
    handle_auth_message(token, state)
  end

  defp handle_parsed_message(%{"type" => type}, state) when is_binary(type) do
    cond do
      State.authenticated?(state) ->
        handle_authenticated_message(%{"type" => type}, state)

      true ->
        Logger.debug("Attempted to send #{type} message before authentication")
        {:error, error_response("Authentication required", "UNAUTHENTICATED")}
    end
  end

  defp handle_parsed_message(_message, _state) do
    {:error, error_response("Invalid message format", "INVALID_TYPE")}
  end

  @doc false
  defp handle_auth_message(token, %State{} = state) do
    if State.authenticated?(state) do
      Logger.warning("Attempted to authenticate already authenticated connection")
      {:error, error_response("Already authenticated", "INVALID_STATE")}
    else
      case Auth.authenticate(token) do
        {:ok, user_id, token_type} ->
          new_state = State.authenticate(state, user_id, token_type, token)
          response = success_response(%{"user_id" => user_id}, "Authenticated successfully")
          {:ok, response, new_state}

        {:error, _reason} ->
          Logger.warning("Authentication failed with provided token")
          {:error, error_response("Invalid or revoked token", "INVALID_TOKEN")}
      end
    end
  end

  @doc false
  defp handle_authenticated_message(%{"type" => "record_play"} = message, state) do
    handle_record_play_message(message, state)
  end

  defp handle_authenticated_message(%{"type" => type}, _state) do
    Logger.debug("Unknown message type: #{type}")
    {:error, error_response("Unknown message type: #{type}", "INVALID_TYPE")}
  end

  @doc false
  defp handle_record_play_message(message, %State{} = state) do
    case validate_record_play_message(message) do
      {:ok, validated_message} ->
        dispatch_play_command(validated_message, state)

      {:error, error_code} ->
        {:error, error_response("Missing or invalid fields for record_play", error_code)}
    end
  end

  @doc false
  defp validate_record_play_message(message) do
    with {:ok, feed} <- extract_required(message, "feed"),
         {:ok, item} <- extract_required(message, "item"),
         {:ok, position} <- extract_position(message),
         {:ok, played} <- extract_played(message) do
      {:ok, %{
        "feed" => feed,
        "item" => item,
        "position" => position,
        "played" => played
      }}
    else
      {:error, code} -> {:error, code}
    end
  end

  @doc false
  defp dispatch_play_command(message, %State{} = state) do
    try do
      command = %RecordPlay{
        user_id: state.user_id,
        rss_source_feed: message["feed"],
        rss_source_item: message["item"],
        position: message["position"],
        played: message["played"],
        event_infos: %{"device_id" => "websocket", "device_name" => "WebSocket Live"}
      }

      case Dispatcher.dispatch(command) do
        :ok ->
          Logger.info("Play event recorded for user #{state.user_id}")
          response = success_response(message, "Play event recorded")
          new_state = State.touch(state)
          {:ok, response, new_state}

        {:error, reason} ->
          Logger.error("Failed to dispatch play command: #{inspect(reason)}")
          {:error, error_response("Failed to record play event", "INTERNAL_ERROR")}
      end
    rescue
      e ->
        Logger.error("Exception while dispatching play command: #{inspect(e)}")
        {:error, error_response("Internal server error", "INTERNAL_ERROR")}
    end
  end

  @doc false
  defp extract_required(message, field) do
    case Map.get(message, field) do
      nil -> {:error, "MISSING_FIELDS"}
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, "INVALID_ENCODING"}
    end
  end

  @doc false
  defp extract_position(message) do
    case Map.get(message, "position") do
      nil -> {:error, "MISSING_FIELDS"}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, "MISSING_FIELDS"}
    end
  end

  @doc false
  defp extract_played(message) do
    case Map.get(message, "played") do
      nil -> {:error, "MISSING_FIELDS"}
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, "MISSING_FIELDS"}
    end
  end

  @doc false
  defp success_response(data, message) do
    Jason.encode!(%{
      "status" => "ok",
      "message" => message,
      "data" => data
    })
  end

  @doc false
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
