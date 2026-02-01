defmodule BaladosSyncWeb.HealthControllerTest do
  use BaladosSyncWeb.ConnCase

  test "GET /api/v1/health returns ok with version", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/health")
    response = json_response(conn, 200)
    assert response["ok"] == true
    assert is_binary(response["version"])
    assert Map.keys(response) |> Enum.sort() == ["ok", "version"]
  end
end
