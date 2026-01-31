defmodule BaladosSyncWeb.HealthController do
  use BaladosSyncWeb, :controller

  def check(conn, _params) do
    version = Application.spec(:balados_sync_web, :vsn) |> to_string()
    json(conn, %{ok: true, version: version})
  end
end
