defmodule BaladosSyncWeb.DashboardController do
  use BaladosSyncWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, user: user)
  end
end
