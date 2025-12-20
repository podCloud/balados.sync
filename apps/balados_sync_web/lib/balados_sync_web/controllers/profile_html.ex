defmodule BaladosSyncWeb.ProfileHTML do
  @moduledoc """
  This module contains pages rendered by ProfileController.
  """
  use BaladosSyncWeb, :html

  embed_templates "profile_html/*"

  @doc """
  Returns the display name for a user (public_name or username).
  """
  def display_name(%{public_name: public_name}) when is_binary(public_name) and public_name != "" do
    public_name
  end

  def display_name(%{username: username}), do: username

  @doc """
  Format a DateTime to a relative time string (e.g., "2 days ago", "just now").
  """
  def time_ago_in_words(nil), do: "Unknown"

  def time_ago_in_words(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    seconds_diff = DateTime.diff(now, datetime, :second)

    cond do
      seconds_diff < 0 -> "in the future"
      seconds_diff < 60 -> "just now"
      seconds_diff < 3600 -> "#{div(seconds_diff, 60)}m ago"
      seconds_diff < 86400 -> "#{div(seconds_diff, 3600)}h ago"
      seconds_diff < 604_800 -> "#{div(seconds_diff, 86400)}d ago"
      seconds_diff < 2_592_000 -> "#{div(seconds_diff, 604_800)}w ago"
      seconds_diff < 31_536_000 -> "#{div(seconds_diff, 2_592_000)}mo ago"
      true -> "#{div(seconds_diff, 31_536_000)}y ago"
    end
  end

  def time_ago_in_words(_), do: "Unknown"

  @doc """
  Returns the Tailwind CSS gradient class for a collection based on its color.
  """
  def collection_color_class(%{color: color}) when is_binary(color) do
    case color do
      "blue" -> "bg-gradient-to-br from-blue-400 to-blue-600"
      "green" -> "bg-gradient-to-br from-green-400 to-green-600"
      "purple" -> "bg-gradient-to-br from-purple-400 to-purple-600"
      "red" -> "bg-gradient-to-br from-red-400 to-red-600"
      "yellow" -> "bg-gradient-to-br from-yellow-400 to-yellow-600"
      "pink" -> "bg-gradient-to-br from-pink-400 to-pink-600"
      "indigo" -> "bg-gradient-to-br from-indigo-400 to-indigo-600"
      "teal" -> "bg-gradient-to-br from-teal-400 to-teal-600"
      _ -> "bg-gradient-to-br from-zinc-400 to-zinc-600"
    end
  end

  def collection_color_class(_), do: "bg-gradient-to-br from-zinc-400 to-zinc-600"
end
