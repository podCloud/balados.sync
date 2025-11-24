defmodule BaladosSyncWeb.AppAuthController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.AppAuth

  @doc """
  GET /authorize?token=...
  Decodes the token and renders an authorization page if user is authenticated.
  If not authenticated, redirects to login page with return_to.
  """
  def authorize(conn, %{"token" => token}) do
    case AppAuth.decode_app_token(token) do
      {:ok, decoded_data} ->
        if conn.assigns[:current_user] do
          # User is authenticated, render authorization page
          render(conn, :authorize,
            app_name: decoded_data["name"],
            app_url: decoded_data["url"],
            app_image: decoded_data["image"],
            scopes: decoded_data["scopes"] || [],
            token: token
          )
        else
          # Not authenticated, redirect to login
          conn
          |> put_session(:user_return_to, current_path(conn))
          |> put_flash(:info, "Please log in to authorize this application.")
          |> redirect(to: ~p"/users/log_in")
        end

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> put_flash(:error, "Invalid authorization token.")
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
  POST /authorize
  Creates the authorization after user confirms.
  Expects "token" in params.
  Requires authenticated user.
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
              conn
              |> put_status(:unprocessable_entity)
              |> put_flash(:error, "Failed to authorize application: #{format_errors(changeset)}")
              |> redirect(to: ~p"/dashboard")
          end

        {:error, _reason} ->
          conn
          |> put_status(:bad_request)
          |> put_flash(:error, "Invalid authorization token.")
          |> redirect(to: ~p"/dashboard")
      end
    else
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
  GET /api/v1/apps
  Lists all authorized apps for the current user (JWT authenticated).
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
  DELETE /api/v1/apps/:jti
  Revokes an app authorization by token_jti (JWT authenticated).
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
