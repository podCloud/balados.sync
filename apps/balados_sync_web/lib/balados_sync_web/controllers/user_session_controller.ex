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
          error_message: gettext("auth.account_locked")
        )

      {:error, :invalid_credentials} ->
        # In order to prevent user enumeration attacks, don't disclose whether the username is registered.
        render(conn, :new, error_message: gettext("auth.invalid_credentials"))
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("auth.logged_out"))
    |> UserAuth.log_out_user()
  end
end
