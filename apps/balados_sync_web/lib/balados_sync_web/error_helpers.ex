defmodule BaladosSyncWeb.ErrorHelpers do
  @moduledoc """
  Helper module for consistent and secure error handling in controllers.

  This module provides functions to handle errors in a way that:
  - Logs full error details server-side for debugging
  - Returns sanitized, user-friendly messages to clients
  - Prevents information leakage through error responses

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

  @doc """
  Standard error response format for JSON APIs.

  Logs the full error for debugging and returns a sanitized response.

  ## Options
    - `:status` - HTTP status code (default: 422 for dispatch errors, 500 for others)
    - `:message` - Custom user-facing message (optional, uses reason-based default)
  """
  def handle_error(conn, reason, opts \\ []) do
    Logger.error("[API Error] #{inspect(reason)}", error: reason)

    status = Keyword.get(opts, :status, 422)
    message = Keyword.get_lazy(opts, :message, fn -> sanitize_reason(reason) end)

    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  @doc """
  Handles dispatch errors from Commanded.

  Returns 422 Unprocessable Entity with a generic message.
  """
  def handle_dispatch_error(conn, reason) do
    Logger.error("[Dispatch Error] #{inspect(reason)}", error: reason)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: sanitize_reason(reason)})
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
  Returns a generic internal server error response.
  """
  def internal_server_error(conn, reason \\ nil) do
    if reason, do: Logger.error("[Internal Error] #{inspect(reason)}", error: reason)

    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end
end
