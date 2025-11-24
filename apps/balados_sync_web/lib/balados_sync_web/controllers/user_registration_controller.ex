defmodule BaladosSyncWeb.UserRegistrationController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.Accounts
  alias BaladosSyncProjections.Schemas.User
  alias BaladosSyncWeb.Plugs.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account created successfully! You can now log in.")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
