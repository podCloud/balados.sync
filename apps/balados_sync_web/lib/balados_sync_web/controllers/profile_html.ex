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
end
