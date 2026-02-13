defmodule BaladosSyncWeb.PageControllerTest do
  use BaladosSyncWeb.ConnCase

  test "GET / redirects to setup when no users exist", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/setup"
  end
end
