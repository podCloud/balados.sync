defmodule BaladosSyncWeb.EndpointBodyLimitTest do
  use BaladosSyncWeb.ConnCase

  @moduletag :body_limit

  describe "request body size limit" do
    test "accepts requests under 1MB", %{conn: conn} do
      # Generate a payload under 1MB (~500KB)
      small_data = String.duplicate("a", 500_000)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/play", Jason.encode!(%{"data" => small_data}))

      # Should not be 413 - might be 401 (unauthorized) but not payload too large
      refute conn.status == 413
    end

    test "rejects requests over 1MB with 413", %{conn: conn} do
      # Generate a payload over 1MB (~1.5MB)
      large_data = String.duplicate("a", 1_500_000)

      # Use assert_error_sent to catch the RequestTooLargeError exception
      # and verify it returns 413
      assert_error_sent 413, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/play", Jason.encode!(%{"data" => large_data}))
      end
    end
  end
end
