defmodule BaladosSyncWeb.SetupController do
  use BaladosSyncWeb, :controller
  alias BaladosSyncWeb.Accounts
  alias BaladosSyncProjections.Schemas.User

  # Affiche la page de setup
  def show(conn, _params) do
    if Accounts.any_users_exist?() do
      # Redirige vers home si déjà configuré
      conn
      |> put_flash(:info, "System already configured")
      |> redirect(to: ~p"/")
    else
      changeset = Accounts.change_user_registration(%User{})
      render(conn, :show, changeset: changeset, layout: false)
    end
  end

  # Crée le premier admin
  def create(conn, %{"setup" => setup_params}) do
    if Accounts.any_users_exist?() do
      # Protection contre race condition
      conn
      |> put_flash(:error, "System already configured")
      |> redirect(to: ~p"/")
    else
      case Accounts.register_admin_user(setup_params) do
        {:ok, user} ->
          conn
          |> put_flash(:info, "Welcome! You are now the admin of this Balados Sync instance.")
          |> BaladosSyncWeb.Plugs.UserAuth.log_in_user(user)
          |> redirect(to: ~p"/admin")

        {:error, %Ecto.Changeset{} = changeset} ->
          render(conn, :show, changeset: changeset, layout: false)
      end
    end
  end
end
