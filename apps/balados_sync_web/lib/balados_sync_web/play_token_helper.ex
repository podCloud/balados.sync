defmodule BaladosSyncWeb.PlayTokenHelper do
  @moduledoc """
  Helper functions for managing PlayTokens used by the play gateway.

  PlayTokens allow authenticated users to track plays through the RSS aggregation gateway
  without requiring full app authentication on each play.

  Supports two play gateway modes:
  1. External domain mode (production): https://{play_domain}/{token}/{feed}/{item}
  2. Local path mode (development, default): /play/{token}/{feed}/{item}

  Configuration:
  - If `play_domain` is set, uses external domain URLs
  - Otherwise, uses local path (/play/) as default (for single-domain development)

  Example config:
    config :balados_sync_web, play_domain: "play.example.com"  # Production
    # or omit for development path mode at /play/
  """

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.PlayToken
  import Ecto.Query

  @doc """
  Gets or creates a PlayToken named "Balados Web" for the user.

  This is used to generate play gateway links in RSS feeds. The token is automatically
  created on first use to avoid requiring users to manually set up tokens.

  Returns {:ok, token_string} on success, {:error, reason} on failure.
  """
  def get_or_create_balados_web_token(user_id) do
    case get_balados_web_token(user_id) do
      {:ok, token} ->
        {:ok, token}

      :not_found ->
        create_balados_web_token(user_id)
    end
  end

  @doc """
  Gets the existing "Balados Web" token for the user, if it exists and is not revoked.

  Returns {:ok, token_string} if found, :not_found if not found or revoked, {:error, reason} on failure.
  """
  def get_balados_web_token(user_id) do
    query =
      from(t in PlayToken,
        where: t.user_id == ^user_id and t.name == "Balados Web" and is_nil(t.revoked_at),
        select: t.token
      )

    case ProjectionsRepo.one(query) do
      nil -> :not_found
      token -> {:ok, token}
    end
  end

  @doc """
  Creates a new "Balados Web" PlayToken for the user.

  Only creates if a valid token doesn't already exist. If one already exists, returns it.

  Returns {:ok, token_string} on success, {:error, reason} on failure.
  """
  def create_balados_web_token(user_id) do
    token = PlayToken.generate_token()

    play_token = %PlayToken{
      user_id: user_id,
      token: token,
      name: "Balados Web"
    }

    case ProjectionsRepo.insert(play_token) do
      {:ok, _} ->
        {:ok, token}

      # If token somehow already exists (race condition), fetch it instead
      {:error, %{errors: [token: {"has already been taken", _}]}} ->
        get_balados_web_token(user_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds a play gateway URL for the given token, feed, and item.

  Intelligently chooses between:
  - External domain mode: https://{play_domain}/{token}/{feed}/{item}
  - Local path mode: /play/{token}/{feed}/{item}

  Configuration:
  - If `play_domain` is set, uses external domain URLs
  - Otherwise, uses local path routes (development default)

  The encoding is applied by the caller for flexibility.
  """
  def build_play_url(token, encoded_feed, item_id_encoded) do
    case Application.get_env(:balados_sync_web, :play_domain) do
      # External domain mode (when play_domain is configured, e.g., "play.example.com")
      play_domain when is_binary(play_domain) ->
        "https://#{play_domain}/#{token}/#{encoded_feed}/#{item_id_encoded}"

      # Local path mode (default when play_domain is not set)
      nil ->
        "/play/#{token}/#{encoded_feed}/#{item_id_encoded}"
    end
  end
end
