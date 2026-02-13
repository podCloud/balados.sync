defmodule BaladosSyncWeb.Helpers.Pagination do
  @moduledoc """
  Shared pagination helpers for controllers.

  Provides utility functions for parsing and validating pagination parameters
  from query strings (limit, offset, etc.).

  ## Usage

  In controllers:

      import BaladosSyncWeb.Helpers.Pagination

      limit = min(safe_parse_int(params["limit"], 50), 100)
      offset = safe_parse_int(params["offset"], 0)
  """

  @doc """
  Safely parses a string value to a non-negative integer, returning the default
  if parsing fails or the value is negative.

  ## Examples

      iex> safe_parse_int("42", 10)
      42

      iex> safe_parse_int("-1", 10)
      10

      iex> safe_parse_int("abc", 10)
      10

      iex> safe_parse_int(nil, 10)
      10
  """
  def safe_parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {val, _} when val >= 0 -> val
      _ -> default
    end
  end

  def safe_parse_int(_, default), do: default
end
