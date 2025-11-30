defmodule BaladosSyncWeb.WebSubscriptionsHTML do
  use BaladosSyncWeb, :html

  embed_templates "web_subscriptions_html/*"

  @doc """
  Format duration in seconds to human readable string.

  Examples:
    format_duration(3661) => "1h 1m"
    format_duration(125) => "2m 5s"
    format_duration(45) => "45s"
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
end
