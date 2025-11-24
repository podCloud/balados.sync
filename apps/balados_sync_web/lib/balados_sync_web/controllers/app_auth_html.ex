defmodule BaladosSyncWeb.AppAuthHTML do
  @moduledoc """
  HTML rendering for app authorization pages.
  """
  use BaladosSyncWeb, :html

  embed_templates "app_auth_html/*"

  @doc """
  Returns a human-readable description for a given scope.
  """
  def scope_description(scope) do
    case scope do
      "read:subscriptions" -> "View your podcast subscriptions"
      "write:subscriptions" -> "Manage your podcast subscriptions"
      "read:play_status" -> "View your listening progress"
      "write:play_status" -> "Update your listening progress"
      "read:playlists" -> "View your playlists"
      "write:playlists" -> "Manage your playlists"
      "read:privacy" -> "View your privacy settings"
      "write:privacy" -> "Manage your privacy settings"
      _ -> scope
    end
  end

  @doc """
  Truncates a URL to a reasonable display length.
  """
  def truncate_url(url, max_length \\ 40) do
    if String.length(url) > max_length do
      String.slice(url, 0, max_length) <> "..."
    else
      url
    end
  end

  @doc """
  Formats a DateTime for display.
  """
  def format_datetime(nil), do: "Never"

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end
end
