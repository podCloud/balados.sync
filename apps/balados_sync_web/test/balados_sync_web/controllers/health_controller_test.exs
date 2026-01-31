defmodule BaladosSyncWeb.HealthControllerTest do
  use BaladosSyncWeb.ConnCase

  test "GET /api/v1/health returns ok", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/health")
    assert json_response(conn, 200) == %{"ok" => true}
  end
end
