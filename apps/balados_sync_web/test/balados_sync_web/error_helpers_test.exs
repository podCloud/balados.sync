defmodule BaladosSyncWeb.ErrorHelpersTest do
  use BaladosSyncWeb.ConnCase, async: true

  import BaladosSyncWeb.ErrorHelpers

  describe "sanitize_reason/1" do
    test "converts atoms to readable strings" do
      assert sanitize_reason(:invalid_token) == "Invalid token"
      assert sanitize_reason(:not_found) == "Not found"
      assert sanitize_reason(:unauthorized) == "Unauthorized"
    end

    test "handles {:error, atom} tuples" do
      assert sanitize_reason({:error, :invalid_input}) == "Invalid input"
    end

    test "handles Ecto.Changeset errors" do
      # Use a proper changeset structure with types
      changeset =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.add_error(:name, "can't be blank")

      result = sanitize_reason(changeset)
      assert result =~ "Name"
      assert result =~ "can't be blank"
    end

    test "truncates long strings" do
      long_string = String.duplicate("a", 300)
      result = sanitize_reason(long_string)
      assert String.length(result) <= 200
    end

    test "redacts sensitive information in strings" do
      assert sanitize_reason("Error at 192.168.1.1") =~ "[IP]"
      assert sanitize_reason("Path /home/user/secret") =~ "[path]"
      assert sanitize_reason("DB postgres://user:pass@host/db") =~ "[db]"
    end

    test "handles unknown types gracefully" do
      assert sanitize_reason(%{complex: "map"}) == "An error occurred"
      assert sanitize_reason([1, 2, 3]) == "An error occurred"
    end

    test "handles tuples with atom first element" do
      assert sanitize_reason({:http_error, 500}) == "Http error"
      assert sanitize_reason({:network_error, :timeout}) == "Network error"
    end
  end

  describe "handle_error/3" do
    test "returns sanitized JSON error response" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:invalid_input)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Invalid input"
    end

    test "uses custom status when provided" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:not_found, status: 404)

      assert conn.status == 404
    end

    test "uses custom message when provided" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:some_error, message: "Custom error message")

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Custom error message"
    end
  end

  describe "handle_dispatch_error/2" do
    test "returns 422 with sanitized error" do
      conn =
        build_conn(:post, "/test")
        |> handle_dispatch_error(:command_failed)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Command failed"
    end
  end

  describe "internal_server_error/2" do
    test "returns 500 with generic message" do
      conn =
        build_conn(:get, "/test")
        |> internal_server_error()

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Internal server error"
    end

    test "logs the reason when provided" do
      # Just verify it doesn't crash
      conn =
        build_conn(:get, "/test")
        |> internal_server_error(:database_connection_failed)

      assert conn.status == 500
    end
  end
end
