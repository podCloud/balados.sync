defmodule BaladosSyncWeb.UserSessionController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.Accounts
  alias BaladosSyncWeb.Plugs.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password} = user_params}) do
    case Accounts.get_user_by_username_and_password(username, password) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user, user_params)

      {:error, :locked} ->
        render(conn, :new,
          error_message:
            "Votre compte a été verrouillé suite à trop de tentatives de connexion échouées. Veuillez contacter le support."
        )

      {:error, :invalid_credentials} ->
        # In order to prevent user enumeration attacks, don't disclose whether the username is registered.
        render(conn, :new, error_message: "Nom d'utilisateur ou mot de passe invalide")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
