defmodule BaladosSyncWeb.AppAuthController do
  require Logger

  @moduledoc """
  Controller for OAuth-style app authorization flow.

  This controller handles the authorization flow for third-party applications
  that want to access user data. Apps present a JWT containing their public key
  and metadata, which users can approve or deny.

  ## Authorization Flow

  1. App creates a JWT with its public key and metadata
  2. App redirects user to `/authorize?token=...`
  3. User logs in (if not already authenticated)
  4. User sees authorization page with app details and requested scopes
  5. User approves, creating an ApiToken record
  6. App can now make API requests using JWTs signed with its private key

  ## Routes

  - `GET /authorize?token=...` - Show authorization page
  - `POST /authorize` - Create authorization after user approval
  - `GET /api/v1/apps` - List authorized apps (JWT authenticated)
  - `DELETE /api/v1/apps/:jti` - Revoke app authorization (JWT authenticated)
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.AppAuth

  @doc """
  Shows the authorization page for a third-party app.

  ## Parameters

  - `token` - JWT containing app metadata and public key

  ## Responses

  - Renders authorization page if user is authenticated
  - Redirects to login if user is not authenticated
  - Redirects with error if token is invalid

  ## Example Request

      GET /authorize?token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
  """
  def authorize(conn, %{"token" => token}) do
    case AppAuth.decode_app_token(token) do
      {:ok, decoded_data} ->
        if conn.assigns[:current_user] do
          Logger.debug("Showing app authorization page for user #{conn.assigns.current_user.id}")
          # User is authenticated, render authorization page
          render(conn, :authorize,
            app_name: decoded_data["app"]["name"],
            app_url: decoded_data["app"]["url"],
            app_image: decoded_data["app"]["image"],
            scopes: decoded_data["scopes"] || [],
            token: token
          )
        else
          Logger.debug("Not authenticated user attempted app authorization")
          # Not authenticated, redirect to login
          conn
          |> put_session(:user_return_to, current_path(conn))
          |> put_flash(:info, "Please log in to authorize this application.")
          |> redirect(to: ~p"/users/log_in")
        end

      {:error, reason} ->
        Logger.debug("Invalid app authorization token: #{reason}")

        conn
        |> put_status(:bad_request)
        |> put_flash(:error, "Invalid authorization token : #{reason}")
        |> redirect(to: ~p"/")
    end
  end

  def authorize(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_flash(:error, "Missing authorization token.")
    |> redirect(to: ~p"/")
  end

  @doc """
  Creates the authorization after user confirms.

  This endpoint is called when the user clicks "Authorize" on the authorization page.
  It decodes the token again, validates it, and creates an ApiToken record.

  ## Parameters

  - `token` - The same JWT from the authorization page

  ## Responses

  - Redirects to dashboard with success message on approval
  - Redirects with error if token is invalid or authorization fails
  - Returns 401 if user is not authenticated

  ## Example Request

      POST /authorize
      Content-Type: application/x-www-form-urlencoded

      token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
  """
  def create_authorization(conn, %{"token" => token}) do
    user = conn.assigns[:current_user]

    if user do
      case AppAuth.decode_app_token(token) do
        {:ok, decoded_data} ->
          case AppAuth.authorize_app(user.id, decoded_data) do
            {:ok, _api_token} ->
              conn
              |> put_flash(:info, "Application authorized successfully!")
              |> redirect(to: ~p"/dashboard")

            {:error, changeset} ->
              Logger.debug(
                "Error authorizing app: #{IO.inspect(changeset)} #{format_errors(changeset)}"
              )

              conn
              |> put_status(:unprocessable_entity)
              |> put_flash(:error, "Failed to authorize application: #{format_errors(changeset)}")
              |> redirect(to: ~p"/dashboard")
          end

        {:error, reason} ->
          Logger.debug("Invalid app authorization token: #{reason}")

          conn
          |> put_status(:bad_request)
          |> put_flash(:error, "Invalid authorization token.")
          |> redirect(to: ~p"/dashboard")
      end
    else
      Logger.debug("Unauthenticated user attempted to create app authorization")
      conn
      |> put_status(:unauthorized)
      |> put_flash(:error, "You must be logged in to authorize applications.")
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def create_authorization(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_flash(:error, "Missing authorization token.")
    |> redirect(to: ~p"/dashboard")
  end

  @doc """
  Lists all authorized apps for the current user.

  Returns a list of all non-revoked app authorizations for the authenticated user.
  Requires JWT authentication via the API.

  ## Authentication

  Requires a valid JWT token in the Authorization header.

  ## Example Request

      GET /api/v1/apps
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response

      {
        "apps": [
          {
            "id": 1,
            "app_name": "Podcast Player Pro",
            "app_url": "https://podcastplayer.com",
            "app_image": "https://podcastplayer.com/icon.png",
            "token_jti": "unique-token-id",
            "scopes": ["read:subscriptions", "write:plays"],
            "last_used_at": "2024-01-15T10:30:00Z",
            "inserted_at": "2024-01-01T08:00:00Z",
            "updated_at": "2024-01-15T10:30:00Z"
          }
        ]
      }
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user_id

    apps = AppAuth.get_authorized_apps(user_id)

    # Transform to JSON-friendly format
    apps_json =
      Enum.map(apps, fn app ->
        %{
          id: app.id,
          app_name: app.app_name,
          app_url: app.app_url,
          app_image: app.app_image,
          token_jti: app.token_jti,
          scopes: app.scopes,
          last_used_at: app.last_used_at,
          inserted_at: app.inserted_at,
          updated_at: app.updated_at
        }
      end)

    json(conn, %{apps: apps_json})
  end

  @doc """
  Revokes an app authorization.

  Removes access for a specific app by marking its authorization as revoked.
  The app will no longer be able to make authenticated requests on behalf of the user.

  ## Parameters

  - `jti` - The unique token identifier (JTI) of the app to revoke

  ## Authentication

  Requires a valid JWT token in the Authorization header.

  ## Example Request

      DELETE /api/v1/apps/unique-token-id
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response (Success)

      {
        "status": "success",
        "message": "App authorization revoked"
      }

  ## Example Response (Not Found)

      {
        "error": "App not found or already revoked"
      }
  """
  def delete(conn, %{"jti" => jti}) do
    user_id = conn.assigns.current_user_id

    case AppAuth.revoke_app(user_id, jti) do
      {:ok, _api_token} ->
        json(conn, %{status: "success", message: "App authorization revoked"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "App not found or already revoked"})
    end
  end

  # Helper function to format changeset errors
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
