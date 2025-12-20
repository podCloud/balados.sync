defmodule BaladosSyncWeb.PlaylistsHTML do
  @moduledoc """
  HTML components for playlists pages.
  """

  use BaladosSyncWeb, :html

  embed_templates "playlists_html/*"

  @doc """
  Returns the count of active items in a playlist.
  Uses the virtual `items_count` field if available (from optimized query),
  otherwise falls back to counting loaded items.
  """
  def item_count(playlist) do
    cond do
      # Use precomputed count from subquery (index page optimization)
      is_integer(playlist.items_count) -> playlist.items_count
      # Fallback to counting loaded items (show page with preload)
      is_list(playlist.items) -> length(playlist.items)
      # Default case
      true -> 0
    end
  end
end
