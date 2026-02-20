defmodule BaladosSyncCore.LikeNormalizer do
  @moduledoc """
  Normalizes nested like data maps to ensure atom keys after JSON deserialization.

  The event store serializes events as JSON, so after replay, nested maps have
  string keys (e.g. "liked_at") instead of atoms (:liked_at). This module
  provides a shared normalization function used by both the Like aggregate
  and the LikeProjector.
  """

  # Explicit whitelist of allowed keys in like data maps.
  # Using a whitelist instead of String.to_existing_atom avoids unhelpful
  # ArgumentError on checkpoint replay if a field is ever renamed.
  # When adding new fields to like data maps, add the mapping here too.
  @allowed_keys %{
    "liked_at" => :liked_at,
    "unliked_at" => :unliked_at,
    "rss_source_feed" => :rss_source_feed
  }

  @doc """
  Normalize a map of like data entries, converting string keys to atoms.

  Unknown string keys are dropped silently to avoid crashes on replay
  with stale checkpoint data.

  ## Examples

      iex> normalize(%{"feed-1" => %{"liked_at" => ~U[2024-01-01 00:00:00Z]}})
      %{"feed-1" => %{liked_at: ~U[2024-01-01 00:00:00Z]}}
  """
  def normalize(likes) when is_map(likes) do
    Map.new(likes, fn {key, value} -> {key, atomize_keys(value)} end)
  end

  def normalize(_), do: %{}

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.flat_map(fn
      {key, value} when is_binary(key) ->
        case Map.fetch(@allowed_keys, key) do
          {:ok, atom_key} -> [{atom_key, value}]
          :error -> []
        end

      {key, value} when is_atom(key) ->
        [{key, value}]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp atomize_keys(value), do: value
end
