defmodule BaladosSyncWeb.UserSessionController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.Accounts
  alias BaladosSyncWeb.Plugs.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user, user_params)

      {:error, :locked} ->
        render(conn, :new,
          error_message:
            "Your account has been locked due to too many failed login attempts. Please contact support."
        )

      {:error, :invalid_credentials} ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        render(conn, :new, error_message: "Invalid email or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
