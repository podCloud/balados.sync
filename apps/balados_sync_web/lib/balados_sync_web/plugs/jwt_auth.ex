defmodule BaladosSyncWeb.Plugs.JWTAuth do
  @moduledoc """
  Plug for JWT-based authentication for third-party apps.

  This plug verifies JWT tokens from authorized apps and optionally checks
  that the app has the required scopes for the requested operation.

  ## Usage

      # In your controller
      plug JWTAuth when action in [:index, :show, :update]

      # With required scopes
      plug JWTAuth, scopes: ["user.subscriptions.read"]

      # With multiple required scopes (all must be granted)
      plug JWTAuth, scopes: ["user.read", "user.subscriptions.read"]

      # With alternative scopes (any one must be granted)
      plug JWTAuth, scopes_any: ["user", "user.subscriptions.read"]

  ## Assigns

  After successful authentication, the following assigns are available:
  - `:current_user_id` - The user ID from the JWT sub claim
  - `:app_token` - The AppToken record from the database
  - `:app_id` - The app ID from the JWT iss claim
  - `:jwt_claims` - All JWT claims
  """

  import Plug.Conn
  import BaladosSyncWeb.ErrorHelpers, only: [unauthorized: 2, forbidden: 2]
  require Logger

  alias BaladosSyncWeb.AppAuth
  alias BaladosSyncWeb.Scopes

  def init(opts), do: opts

  def call(conn, opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{claims: claims, app_token: app_token}} <- AppAuth.verify_app_request(token),
         :ok <- check_scopes(app_token.scopes, opts) do
      conn
      |> assign(:current_user_id, claims["sub"])
      |> assign(:app_token, app_token)
      |> assign(:app_id, claims["iss"])
      |> assign(:jwt_claims, claims)
      |> assign(:device_id, claims["device_id"] || app_token.app_id)
      |> assign(:device_name, claims["device_name"] || app_token.app_name)
    else
      {:error, :insufficient_scopes} = error ->
        Logger.debug("JWT auth failed: #{inspect(error)}")

        conn
        |> forbidden("Insufficient permissions")
        |> halt()

      error ->
        Logger.debug("JWT auth failed: #{inspect(error)}")

        conn
        |> unauthorized("Unauthorized")
        |> halt()
    end
  end

  # Check if the granted scopes satisfy the required scopes
  defp check_scopes(_granted_scopes, []), do: :ok

  defp check_scopes(granted_scopes, opts) do
    cond do
      # Check if all required scopes are granted
      required_scopes = Keyword.get(opts, :scopes) ->
        if Scopes.authorized_all?(granted_scopes, required_scopes) do
          :ok
        else
          {:error, :insufficient_scopes}
        end

      # Check if any of the alternative scopes are granted
      scopes_any = Keyword.get(opts, :scopes_any) ->
        if Scopes.authorized_any?(granted_scopes, scopes_any) do
          :ok
        else
          {:error, :insufficient_scopes}
        end

      true ->
        :ok
    end
  end
end
