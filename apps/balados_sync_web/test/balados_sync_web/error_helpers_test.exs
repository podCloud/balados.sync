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
    test "returns sanitized JSON error response with error_code" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:invalid_input)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Invalid input"
      assert body["error_code"] == "VALIDATION_ERROR"
    end

    test "uses custom status when provided" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:not_found, status: 404)

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error_code"] == "NOT_FOUND"
    end

    test "uses custom message when provided" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:some_error, message: "Custom error message")

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Custom error message"
    end

    test "uses explicit error code when provided" do
      conn =
        build_conn(:post, "/test")
        |> handle_error(:some_error, code: "CUSTOM_CODE")

      body = Jason.decode!(conn.resp_body)
      assert body["error_code"] == "CUSTOM_CODE"
    end
  end

  describe "handle_dispatch_error/2" do
    test "returns 422 with sanitized error and VALIDATION_ERROR code" do
      conn =
        build_conn(:post, "/test")
        |> handle_dispatch_error(:command_failed)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Command failed"
      assert body["error_code"] == "VALIDATION_ERROR"
    end
  end

  describe "internal_server_error/2" do
    test "returns 500 with generic message and INTERNAL_ERROR code" do
      conn =
        build_conn(:get, "/test")
        |> internal_server_error()

      assert conn.status == 500
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Internal server error"
      assert body["error_code"] == "INTERNAL_ERROR"
    end

    test "logs the reason when provided" do
      # Just verify it doesn't crash
      conn =
        build_conn(:get, "/test")
        |> internal_server_error(:database_connection_failed)

      assert conn.status == 500
    end
  end

  describe "unauthorized/2" do
    test "returns 401 with UNAUTHORIZED code" do
      conn =
        build_conn(:get, "/test")
        |> unauthorized()

      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Unauthorized"
      assert body["error_code"] == "UNAUTHORIZED"
    end

    test "uses custom message" do
      conn =
        build_conn(:get, "/test")
        |> unauthorized("Invalid token")

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Invalid token"
      assert body["error_code"] == "UNAUTHORIZED"
    end
  end

  describe "forbidden/2" do
    test "returns 403 with FORBIDDEN code" do
      conn =
        build_conn(:get, "/test")
        |> forbidden()

      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Insufficient permissions"
      assert body["error_code"] == "FORBIDDEN"
    end
  end

  describe "not_found/2" do
    test "returns 404 with NOT_FOUND code" do
      conn =
        build_conn(:get, "/test")
        |> not_found()

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Not found"
      assert body["error_code"] == "NOT_FOUND"
    end
  end

  describe "rate_limit_exceeded/2" do
    test "returns 429 with RATE_LIMIT_EXCEEDED code" do
      conn =
        build_conn(:get, "/test")
        |> rate_limit_exceeded()

      assert conn.status == 429
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "rate_limit_exceeded"
      assert body["error_code"] == "RATE_LIMIT_EXCEEDED"
      assert get_resp_header(conn, "retry-after") == ["60"]
    end

    test "uses custom retry-after value" do
      conn =
        build_conn(:get, "/test")
        |> rate_limit_exceeded(120)

      assert get_resp_header(conn, "retry-after") == ["120"]
    end
  end
end
