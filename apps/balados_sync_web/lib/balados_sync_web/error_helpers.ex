defmodule BaladosSyncWeb.ErrorHelpers do
  @moduledoc """
  Helper module for consistent and secure error handling in controllers.

  This module provides functions to handle errors in a way that:
  - Logs full error details server-side for debugging
  - Returns sanitized, user-friendly messages to clients
  - Provides machine-readable error codes for programmatic handling
  - Prevents information leakage through error responses

  ## Error Codes

  All API errors include an `error_code` field with one of:
  - `UNAUTHORIZED` - Authentication required or invalid token
  - `FORBIDDEN` - Valid auth but insufficient permissions
  - `NOT_FOUND` - Requested resource doesn't exist
  - `VALIDATION_ERROR` - Input validation failed
  - `RATE_LIMIT_EXCEEDED` - Too many requests
  - `INTERNAL_ERROR` - Server-side error

  ## Usage

  In controllers:

      import BaladosSyncWeb.ErrorHelpers

      case Dispatcher.dispatch(command) do
        :ok ->
          json(conn, %{status: "success"})

        {:error, reason} ->
          handle_dispatch_error(conn, reason)
      end

  Or with flash messages:

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
    validation_error: "VALIDATION_ERROR",
    rate_limit_exceeded: "RATE_LIMIT_EXCEEDED",
    internal_error: "INTERNAL_ERROR"
  }

  @doc """
  Standard error response format for JSON APIs.

  Logs the full error for debugging and returns a sanitized response with error code.

  ## Options
    - `:status` - HTTP status code (default: 422 for dispatch errors, 500 for others)
    - `:message` - Custom user-facing message (optional, uses reason-based default)
    - `:code` - Error code atom (optional, inferred from status/reason)
  """
  def handle_error(conn, reason, opts \\ []) do
    Logger.error("[API Error] #{inspect(reason)}", error: reason)

    status = Keyword.get(opts, :status, 422)
    message = Keyword.get_lazy(opts, :message, fn -> sanitize_reason(reason) end)
    code = Keyword.get_lazy(opts, :code, fn -> infer_error_code(status, reason) end)

    conn
    |> put_status(status)
    |> json(%{error: message, error_code: code})
  end

  @doc """
  Handles dispatch errors from Commanded.

  Returns 422 Unprocessable Entity with a validation error code.
  """
  def handle_dispatch_error(conn, reason) do
    Logger.error("[Dispatch Error] #{inspect(reason)}", error: reason)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: sanitize_reason(reason), error_code: @error_codes.validation_error})
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

  @doc """
  Returns a generic internal server error response with error code.
  """
  def internal_server_error(conn, reason \\ nil) do
    if reason, do: Logger.error("[Internal Error] #{inspect(reason)}", error: reason)

    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error", error_code: @error_codes.internal_error})
  end

  @doc """
  Returns an unauthorized error response with error code.
  """
  def unauthorized(conn, message \\ "Unauthorized") do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: message, error_code: @error_codes.unauthorized})
  end

  @doc """
  Returns a forbidden error response with error code.
  """
  def forbidden(conn, message \\ "Insufficient permissions") do
    conn
    |> put_status(:forbidden)
    |> json(%{error: message, error_code: @error_codes.forbidden})
  end

  @doc """
  Returns a not found error response with error code.
  """
  def not_found(conn, message \\ "Not found") do
    conn
    |> put_status(:not_found)
    |> json(%{error: message, error_code: @error_codes.not_found})
  end

  @doc """
  Returns a rate limit exceeded error response with error code.
  """
  def rate_limit_exceeded(conn, retry_after \\ 60) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", to_string(retry_after))
    |> json(%{error: "rate_limit_exceeded", error_code: @error_codes.rate_limit_exceeded})
  end

  # Private helpers

  defp infer_error_code(status, _reason) do
    case status do
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
      _ -> @error_codes.validation_error
    end
  end
end
