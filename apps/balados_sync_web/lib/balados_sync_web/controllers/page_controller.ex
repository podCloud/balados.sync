defmodule BaladosSyncWeb.PageController do
  use BaladosSyncWeb, :controller
  alias BaladosSyncWeb.Accounts

  def home(conn, _params) do
    # Rediriger vers setup si aucun utilisateur n'existe
    if Accounts.any_users_exist?() do
      # The home page is often custom made,
      # so skip the default app layout.
      render(conn, :home, layout: false)
    else
      redirect(conn, to: ~p"/setup")
    end
  end

  def app_creator(conn, _params) do
    # App creator utility page for generating JWT tokens
    # No authentication required - all operations are client-side
    render(conn, :app_creator, layout: false)
  end
end
