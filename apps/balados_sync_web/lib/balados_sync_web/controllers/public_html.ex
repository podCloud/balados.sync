defmodule BaladosSyncWeb.PublicHTML do
  use BaladosSyncWeb, :html

  embed_templates "public_html/*"

  @doc """
  Format duration in seconds to human readable string.
  """
  def format_duration(nil), do: "Unknown"

  def format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  def format_duration(_), do: "Unknown"

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
  Get event type color for border styling.
  """
  def event_border_color("subscribe"), do: "border-green-400"
  def event_border_color("play"), do: "border-blue-400"
  def event_border_color("unsubscribe"), do: "border-red-400"
  def event_border_color(_), do: "border-zinc-300"

  @doc """
  Display username or "Anonymous" based on privacy level.
  """
  def display_username(%{"privacy" => "anonymous"}), do: "Anonymous"
  def display_username(%{"username" => nil}), do: "Anonymous"
  def display_username(%{"username" => username}), do: "@#{username}"
  def display_username(_), do: "Anonymous"

  @doc """
  Get event action text based on event type.
  """
  def event_action_text("subscribe"), do: " subscribed to "
  def event_action_text("play"), do: " listened to "
  def event_action_text("unsubscribe"), do: " unsubscribed from "
  def event_action_text(_), do: " interacted with "

  @doc """
  Get podcast title from event with fallback.
  """
  def podcast_title(%{"feed_metadata" => %{"title" => title}}) when is_binary(title), do: title
  def podcast_title(%{"event_data" => %{"feed_title" => title}}) when is_binary(title), do: title
  def podcast_title(_), do: "Unknown Podcast"
end
