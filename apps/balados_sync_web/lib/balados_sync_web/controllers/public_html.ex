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
end
