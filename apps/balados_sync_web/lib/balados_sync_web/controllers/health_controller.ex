defmodule BaladosSyncWeb.HealthController do
  use BaladosSyncWeb, :controller

  def check(conn, _params) do
    json(conn, %{ok: true})
  end
end
