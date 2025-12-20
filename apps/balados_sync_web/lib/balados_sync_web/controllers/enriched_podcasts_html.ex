defmodule BaladosSyncWeb.EnrichedPodcastsHTML do
  use BaladosSyncWeb, :html
  embed_templates "enriched_podcasts_html/*"

  @doc """
  Returns the icon name for a social network type.
  """
  def social_icon(type) do
    case type do
      "twitter" -> "brand-x"
      "mastodon" -> "brand-mastodon"
      "instagram" -> "brand-instagram"
      "youtube" -> "brand-youtube"
      "spotify" -> "brand-spotify"
      "apple_podcasts" -> "brand-apple"
      _ -> "link"
    end
  end

  @doc """
  Returns the display name for a social network type.
  """
  def social_name(type) do
    case type do
      "twitter" -> "Twitter/X"
      "mastodon" -> "Mastodon"
      "instagram" -> "Instagram"
      "youtube" -> "YouTube"
      "spotify" -> "Spotify"
      "apple_podcasts" -> "Apple Podcasts"
      "custom" -> "Custom Link"
      _ -> String.capitalize(type)
    end
  end
end
