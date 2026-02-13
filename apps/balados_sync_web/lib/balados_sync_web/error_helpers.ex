defmodule BaladosSyncWeb.ErrorHelpers do
  @moduledoc """
  Helper module for consistent and secure error handling in controllers.

  This module provides functions to handle errors in a way that:
  - Logs full error details server-side for debugging
  - Returns sanitized, user-friendly messages to clients
  - Provides machine-readable error codes for programmatic handling
  - Prevents information leakage through error responses

  ## Standardized Error Response Format

  All API error responses use the format:

      %{error: "ERROR_CODE", message: "Human-readable description"}

  ## Error Codes

  - `UNAUTHORIZED` - Authentication required or invalid token
  - `FORBIDDEN` - Valid auth but insufficient permissions
  - `NOT_FOUND` - Requested resource doesn't exist
  - `BAD_REQUEST` - Missing or invalid request parameters
  - `VALIDATION_ERROR` - Input validation failed (e.g., dispatch errors)
  - `BAD_GATEWAY` - Upstream service failure
  - `RATE_LIMIT_EXCEEDED` - Too many requests
  - `INTERNAL_ERROR` - Server-side error
  - `SYNC_ERROR` - Sync transaction failure

  ## Usage

  In controllers:

      import BaladosSyncWeb.ErrorHelpers

      case Dispatcher.dispatch(command) do
        :ok ->
          json(conn, %{status: "success"})

        {:error, reason} ->
          handle_dispatch_error(conn, reason)
      end

  Or with specific error helpers:

      bad_request(conn, "Missing required parameters")
      not_found(conn, "Podcast not found")
      internal_server_error(conn, reason)

  Or with flash messages for web pages:

      case SomeContext.do_something() do
        {:ok, result} ->
          redirect(conn, to: ~p"/success")

        {:error, reason} ->
          handle_error_with_flash(conn, reason, ~p"/fallback")
      end
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2, put_flash: 3, redirect: 2]
  require Logger

  # Standard error codes
  @error_codes %{
    unauthorized: "UNAUTHORIZED",
    forbidden: "FORBIDDEN",
    not_found: "NOT_FOUND",
    bad_request: "BAD_REQUEST",
    validation_error: "VALIDATION_ERROR",
    bad_gateway: "BAD_GATEWAY",
    rate_limit_exceeded: "RATE_LIMIT_EXCEEDED",
    internal_error: "INTERNAL_ERROR",
    sync_error: "SYNC_ERROR"
  }

  @doc """
  Returns the standard error codes map. Useful for external modules.
  """
  def error_codes, do: @error_codes

  @doc """
  Builds a standardized error response map.

  ## Examples

      error_response("NOT_FOUND", "Podcast not found")
      #=> %{error: "NOT_FOUND", message: "Podcast not found"}
  """
  def error_response(code, message) do
    %{error: code, message: message}
  end

  @doc """
  Standard error response format for JSON APIs.

  Logs the full error for debugging and returns a sanitized response with error code.

  ## Options
    - `:status` - HTTP status code (default: 422 for dispatch errors, 500 for others)
    - `:message` - Custom user-facing message (optional, uses reason-based default)
    - `:code` - Error code string (optional, inferred from status/reason)
  """
  def handle_error(conn, reason, opts \\ []) do
    Logger.error("[API Error] #{inspect(reason)}", error: reason)

    status = Keyword.get(opts, :status, 422)
    message = Keyword.get_lazy(opts, :message, fn -> sanitize_reason(reason) end)
    code = Keyword.get_lazy(opts, :code, fn -> infer_error_code(status, reason) end)

    conn
    |> put_status(status)
    |> json(error_response(code, message))
  end

  @doc """
  Handles dispatch errors from Commanded.

  Returns 422 Unprocessable Entity with a VALIDATION_ERROR code.
  """
  def handle_dispatch_error(conn, reason) do
    Logger.error("[Dispatch Error] #{inspect(reason)}", error: reason)

    conn
    |> put_status(:unprocessable_entity)
    |> json(error_response(@error_codes.validation_error, sanitize_reason(reason)))
  end

  @doc """
  Handles errors with flash messages for web pages.

  Logs the full error and redirects with a sanitized flash message.
  """
  def handle_error_with_flash(conn, reason, redirect_to, opts \\ []) do
    Logger.error("[Web Error] #{inspect(reason)}", error: reason)

    message =
      Keyword.get_lazy(opts, :message, fn ->
        "An error occurred: #{sanitize_reason(reason)}"
      end)

    conn
    |> put_flash(:error, message)
    |> redirect(to: redirect_to)
  end

  @doc """
  Sanitizes an error reason to a user-friendly message.

  Converts internal error tuples and atoms to readable messages without
  exposing internal details like module names or stack traces.
  """
  def sanitize_reason(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def sanitize_reason({:error, reason}) when is_atom(reason) do
    sanitize_reason(reason)
  end

  def sanitize_reason(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    errors
    |> Enum.map(fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
    |> case do
      "" -> "Validation error"
      msg -> msg
    end
  end

  def sanitize_reason(reason) when is_binary(reason) do
    # Truncate very long messages and remove potential sensitive info
    reason
    |> String.slice(0, 200)
    |> String.replace(~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, "[IP]")
    |> String.replace(~r/\/home\/[^\s]+/, "[path]")
    |> String.replace(~r/postgres:\/\/[^\s]+/, "[db]")
  end

  def sanitize_reason({error_type, _details}) when is_atom(error_type) do
    sanitize_reason(error_type)
  end

  def sanitize_reason(_reason) do
    "An error occurred"
  end

  # ===== Convenience error response functions =====

  @doc """
  Returns a 400 Bad Request error response.
  """
  def bad_request(conn, message \\ "Bad request") do
    conn
    |> put_status(:bad_request)
    |> json(error_response(@error_codes.bad_request, message))
  end

  @doc """
  Returns a 401 Unauthorized error response.
  """
  def unauthorized(conn, message \\ "Unauthorized") do
    conn
    |> put_status(:unauthorized)
    |> json(error_response(@error_codes.unauthorized, message))
  end

  @doc """
  Returns a 403 Forbidden error response.
  """
  def forbidden(conn, message \\ "Insufficient permissions") do
    conn
    |> put_status(:forbidden)
    |> json(error_response(@error_codes.forbidden, message))
  end

  @doc """
  Returns a 404 Not Found error response.
  """
  def not_found(conn, message \\ "Not found") do
    conn
    |> put_status(:not_found)
    |> json(error_response(@error_codes.not_found, message))
  end

  @doc """
  Returns a 422 Unprocessable Entity (validation) error response.
  """
  def validation_error(conn, message \\ "Validation error") do
    conn
    |> put_status(:unprocessable_entity)
    |> json(error_response(@error_codes.validation_error, message))
  end

  @doc """
  Returns a 500 Internal Server Error response.
  Logs the reason when provided.
  """
  def internal_server_error(conn, reason \\ nil) do
    if reason, do: Logger.error("[Internal Error] #{inspect(reason)}", error: reason)

    conn
    |> put_status(:internal_server_error)
    |> json(error_response(@error_codes.internal_error, "Internal server error"))
  end

  @doc """
  Returns a 502 Bad Gateway error response.
  """
  def bad_gateway(conn, message \\ "Upstream service error") do
    conn
    |> put_status(:bad_gateway)
    |> json(error_response(@error_codes.bad_gateway, message))
  end

  @doc """
  Returns a 429 Rate Limit Exceeded error response.
  """
  def rate_limit_exceeded(conn, retry_after \\ 60) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", to_string(retry_after))
    |> json(
      error_response(
        @error_codes.rate_limit_exceeded,
        "Too many requests. Please try again later."
      )
    )
  end

  # Private helpers

  defp infer_error_code(status, _reason) do
    case status do
      400 -> @error_codes.bad_request
      :bad_request -> @error_codes.bad_request
      401 -> @error_codes.unauthorized
      :unauthorized -> @error_codes.unauthorized
      403 -> @error_codes.forbidden
      :forbidden -> @error_codes.forbidden
      404 -> @error_codes.not_found
      :not_found -> @error_codes.not_found
      429 -> @error_codes.rate_limit_exceeded
      :too_many_requests -> @error_codes.rate_limit_exceeded
      500 -> @error_codes.internal_error
      :internal_server_error -> @error_codes.internal_error
      502 -> @error_codes.bad_gateway
      :bad_gateway -> @error_codes.bad_gateway
      _ -> @error_codes.validation_error
    end
  end
end
