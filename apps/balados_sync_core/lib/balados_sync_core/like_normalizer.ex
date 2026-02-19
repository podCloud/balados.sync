defmodule BaladosSyncCore.LikeNormalizer do
  @moduledoc """
  Normalizes nested like data maps to ensure atom keys after JSON deserialization.

  The event store serializes events as JSON, so after replay, nested maps have
  string keys (e.g. "liked_at") instead of atoms (:liked_at). This module
  provides a shared normalization function used by both the Like aggregate
  and the LikeProjector.
  """

  @doc """
  Normalize a map of like data entries, converting string keys to atoms.

  ## Examples

      iex> normalize(%{"feed-1" => %{"liked_at" => ~U[2024-01-01 00:00:00Z]}})
      %{"feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z]}}
  """
  def normalize(likes) when is_map(likes) do
    Map.new(likes, fn {key, value} -> {key, atomize_keys(value)} end)
  end

  def normalize(_), do: %{}

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp atomize_keys(value), do: value
end
