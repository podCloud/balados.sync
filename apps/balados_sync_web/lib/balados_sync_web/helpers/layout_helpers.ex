defmodule BaladosSyncWeb.LayoutHelpers do
  @moduledoc """
  Helper functions for shared layout templates.

  Provides conn/socket-agnostic access to request path and query params,
  so layouts work in both regular controller views and LiveView contexts.
  """

  @doc """
  Returns the current request path from conn or socket assigns.

  Falls back to "/" if neither is available.
  """
  def current_path(%{conn: %{request_path: path}}), do: path
  def current_path(%{socket: %{private: %{live_path: path}}}), do: path
  def current_path(_), do: "/"

  @doc """
  Returns the current query params from conn assigns.

  Returns an empty map in LiveView contexts (socket has no query params).
  """
  def current_params(%{conn: %{query_params: params}}) when is_map(params), do: params
  def current_params(_), do: %{}

  @doc """
  Returns the active nav link class based on the current path.
  """
  def nav_link_class(current_path, path_prefix) do
    if String.starts_with?(current_path, path_prefix) do
      "text-blue-600 border-b-2 border-blue-600"
    else
      "hover:text-zinc-700"
    end
  end
end
