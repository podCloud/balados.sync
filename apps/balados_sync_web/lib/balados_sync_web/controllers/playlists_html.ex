defmodule BaladosSyncWeb.PlaylistsHTML do
  @moduledoc """
  HTML components for playlists pages.
  """

  use BaladosSyncWeb, :html

  embed_templates "playlists_html/*"

  @doc """
  Returns the count of active items in a playlist.
  """
  def item_count(playlist) do
    length(playlist.items || [])
  end
end
