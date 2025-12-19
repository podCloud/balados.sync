defmodule BaladosSyncWeb.LiveWebSocket.MessageHandler do
  @moduledoc """
  Message handler for the LiveWebSocket.

  Parses and validates incoming JSON messages, authenticates if needed, and dispatches commands.
  """

  require Logger
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.RecordPlay
  alias BaladosSyncWeb.LiveWebSocket.{Auth, State}

  # Rate limiting: 10 record_play messages per second per user
  # Scale in milliseconds: 1_000 ms = 1 second
  @rate_limit_scale 1_000
  @rate_limit_limit 10

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
  defp handle_parsed_message(%{"type" => "auth", "token" => token} = message, state) do
    device_id = Map.get(message, "device_id")
    device_name = Map.get(message, "device_name")
    handle_auth_message(token, device_id, device_name, state)
  end

  defp handle_parsed_message(%{"type" => type} = message, state) when is_binary(type) do
    cond do
      State.authenticated?(state) ->
        handle_authenticated_message(message, state)

      true ->
        Logger.debug("Attempted to send #{type} message before authentication")
        {:error, error_response("Authentication required", "UNAUTHENTICATED")}
    end
  end

  defp handle_parsed_message(_message, _state) do
    {:error, error_response("Invalid message format", "INVALID_TYPE")}
  end

  @doc false
  defp handle_auth_message(token, device_id, device_name, %State{} = state) do
    if State.authenticated?(state) do
      Logger.warning("Attempted to authenticate already authenticated connection")
      {:error, error_response("Already authenticated", "INVALID_STATE")}
    else
      case Auth.authenticate(token) do
        {:ok, user_id, token_type} ->
          opts = build_auth_opts(device_id, device_name)
          new_state = State.authenticate(state, user_id, token_type, token, opts)
          response = success_response(%{"user_id" => user_id}, "Authenticated successfully")
          {:ok, response, new_state}

        {:error, reason} ->
          Logger.warning("Authentication failed: #{inspect(reason)}")
          error_msg = format_auth_error(reason)
          {:error, error_response(error_msg, "INVALID_TOKEN")}
      end
    end
  end

  @doc false
  defp build_auth_opts(device_id, device_name) do
    []
    |> maybe_add_opt(:device_id, device_id)
    |> maybe_add_opt(:device_name, device_name)
  end

  @doc false
  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, ""), do: opts
  defp maybe_add_opt(opts, key, value) when is_binary(value), do: Keyword.put(opts, key, value)
  defp maybe_add_opt(opts, _key, _value), do: opts

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
    opid = Map.get(message, "opid")

    case validate_record_play_message(message) do
      {:ok, validated_message} ->
        dispatch_play_command(validated_message, opid, state)

      {:error, error_code} ->
        {:error,
         error_response_with_opid("Missing or invalid fields for record_play", error_code, opid)}
    end
  end

  @doc false
  defp validate_record_play_message(message) do
    Logger.debug("[MessageHandler] Validating record_play message: #{inspect(message)}")

    result =
      with {:ok, feed} <- extract_required(message, "feed"),
           {:ok, item} <- extract_required(message, "item"),
           {:ok, position} <- extract_position(message),
           {:ok, played} <- extract_played(message),
           {:ok, privacy} <- extract_privacy(message) do
        Logger.debug(
          "[MessageHandler] Validation successful: feed=#{feed}, item=#{item}, privacy=#{privacy}"
        )

        {:ok,
         %{
           "feed" => feed,
           "item" => item,
           "position" => position,
           "played" => played,
           "privacy" => privacy
         }}
      else
        {:error, code} ->
          Logger.error(
            "[MessageHandler] Validation failed with code: #{code}, message: #{inspect(message)}"
          )

          {:error, code}
      end

    result
  end

  @doc false
  defp dispatch_play_command(message, opid, %State{} = state) do
    # Check rate limit before dispatching
    rate_limit_key = "websocket_play:#{state.user_id}"

    case Hammer.check_rate(rate_limit_key, @rate_limit_scale, @rate_limit_limit) do
      {:allow, _count} ->
        do_dispatch_play_command(message, opid, state)

      {:deny, _limit} ->
        Logger.warning("Play command rate limit exceeded for user #{state.user_id}")

        {:error,
         error_response_with_opid(
           "Too many play events. Limited to #{@rate_limit_limit} per second.",
           "PLAY_RATE_LIMITED",
           opid
         )}
    end
  end

  @doc false
  defp do_dispatch_play_command(message, opid, %State{} = state) do
    try do
      event_infos = %{
        "device_id" => state.device_id,
        "device_name" => state.device_name,
        "privacy" => message["privacy"]
      }

      command = %RecordPlay{
        user_id: state.user_id,
        rss_source_feed: message["feed"],
        rss_source_item: message["item"],
        position: message["position"],
        played: message["played"],
        event_infos: event_infos
      }

      case Dispatcher.dispatch(command) do
        :ok ->
          Logger.info("Play event recorded for user #{state.user_id}")
          response = success_response_with_opid(message, "Play event recorded", opid)
          new_state = State.touch(state)
          {:ok, response, new_state}

        {:error, reason} ->
          Logger.error("Failed to dispatch play command: #{inspect(reason)}")
          error_msg = "Failed to record play event: #{format_dispatch_error(reason)}"
          {:error, error_response_with_opid(error_msg, "DISPATCH_ERROR", opid)}
      end
    rescue
      e ->
        Logger.error("Exception while dispatching play command: #{inspect(e)}")
        {:error, error_response_with_opid("Internal server error", "INTERNAL_ERROR", opid)}
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
      nil -> {:ok, 0}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, "INVALID_POSITION"}
    end
  end

  @doc false
  defp extract_played(message) do
    case Map.get(message, "played") do
      nil -> {:ok, false}
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, "INVALID_PLAYED"}
    end
  end

  @doc false
  defp extract_privacy(message) do
    case Map.get(message, "privacy") do
      nil -> {:ok, nil}
      "public" -> {:ok, "public"}
      "anonymous" -> {:ok, "anonymous"}
      "private" -> {:ok, "private"}
      _ -> {:error, "INVALID_PRIVACY"}
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

  @doc false
  defp success_response_with_opid(data, message, opid) do
    Jason.encode!(%{
      "status" => "ok",
      "message" => message,
      "data" => data,
      "opid" => opid
    })
  end

  @doc false
  defp error_response_with_opid(message, code, opid) do
    Jason.encode!(%{
      "status" => "error",
      "error" => %{
        "message" => message,
        "code" => code
      },
      "opid" => opid
    })
  end

  @doc false
  defp format_auth_error(:invalid_token), do: "Invalid or revoked token"

  defp format_auth_error(:insufficient_scope),
    do: "Token does not have required scopes for play recording"

  defp format_auth_error(reason), do: inspect(reason)

  @doc false
  defp format_dispatch_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_dispatch_error(reason) when is_binary(reason), do: reason
  defp format_dispatch_error(reason), do: inspect(reason)
end
