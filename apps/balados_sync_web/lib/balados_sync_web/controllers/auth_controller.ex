defmodule BaladosSyncWeb.AuthController do
  @moduledoc """
  Controller for authentication-related endpoints.

  ## Endpoints

  - `POST /api/v1/auth/refresh` - Verify token validity and return app info for renewal

  ## Token Refresh Flow

  The balados.sync authentication system uses asymmetric JWT tokens where:
  1. Apps keep their private key secret and sign their own JWTs
  2. Server stores only the public key to verify signatures
  3. Tokens are short-lived (typically 1 hour `exp` claim)

  The refresh endpoint allows apps to verify their authorization is still valid
  and get the information needed to create a new JWT with a fresh expiration.

  ## Usage

  1. App sends current (valid) JWT to `/api/v1/auth/refresh`
  2. Server verifies JWT and checks app is not revoked
  3. Server returns app info (scopes, user_id, app_id)
  4. App creates new JWT with fresh `exp` time, signed with private key
  """

  use BaladosSyncWeb, :controller

  require Logger

  alias BaladosSyncWeb.AppAuth
  alias BaladosSyncWeb.Plugs.RateLimiter
  import BaladosSyncWeb.ErrorHelpers, only: [unauthorized: 2]

  # Rate limit refresh operations: 100 requests per hour per user
  plug RateLimiter,
    limit: 100,
    window_ms: 3_600_000,
    key: :user_id,
    namespace: "auth_refresh"

  @doc """
  Verifies the current token is valid and returns app information for renewal.

  The client must create new JWTs with their private key - the server does not
  issue tokens. This endpoint simply confirms the authorization is still active
  and returns the necessary information for creating a new JWT.

  ## Authentication

  Requires a valid JWT token in the Authorization header.

  ## Example Request

      POST /api/v1/auth/refresh
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response (Success)

      {
        "status": "success",
        "user_id": "user_abc123",
        "app_id": "com.example.podcast-player",
        "scopes": ["user.subscriptions.read", "user.plays.write"],
        "expires_in": 3600,
        "message": "Authorization valid. Create new JWT with fresh expiration."
      }

  ## Example Response (Unauthorized)

      HTTP 401
      {
        "error": "unauthorized",
        "message": "App authorization has been revoked"
      }
  """
  def refresh(conn, _params) do
    user_id = conn.assigns.current_user_id
    app_id = conn.assigns.app_id

    case AppAuth.get_app_token(user_id, app_id) do
      {:ok, app_token} ->
        Logger.debug("Token refresh successful for app #{app_id} user #{user_id}")

        json(conn, %{
          status: "success",
          user_id: user_id,
          app_id: app_id,
          scopes: app_token.scopes,
          expires_in: 3600,
          message: "Authorization valid. Create new JWT with fresh expiration."
        })

      {:error, :token_not_found} ->
        Logger.info(
          "Token refresh failed: app #{app_id} not found or revoked for user #{user_id}"
        )

        unauthorized(conn, "App authorization has been revoked")
    end
  end
end
