defmodule BaladosSyncWeb.AuthControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.AppToken
  alias BaladosSyncWeb.JwtTestHelper

  @moduletag :auth_controller

  describe "POST /api/v1/auth/refresh - authentication" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/refresh")

      response = json_response(conn, 401)
      assert response["error"] == "UNAUTHORIZED"
      assert response["message"] == "Unauthorized"
    end

    test "returns 401 with invalid JWT", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> post("/api/v1/auth/refresh")

      response = json_response(conn, 401)
      assert response["error"] == "UNAUTHORIZED"
    end
  end

  describe "POST /api/v1/auth/refresh - token refresh" do
    setup do
      user_id = Ecto.UUID.generate()
      {:ok, user_id: user_id}
    end

    test "returns success with valid token and app info", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id,
          scopes: ["user.subscriptions.read", "user.plays.write"]
        )
        |> post("/api/v1/auth/refresh")

      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["user_id"] == user_id
      assert is_binary(response["app_id"])
      assert is_list(response["scopes"])
      assert "user.subscriptions.read" in response["scopes"]
      assert "user.plays.write" in response["scopes"]
      assert response["expires_in"] == 3600
      assert is_binary(response["message"])
    end

    test "returns success with wildcard scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["*"])
        |> post("/api/v1/auth/refresh")

      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["scopes"] == ["*"]
    end

    test "returns 401 when app has been revoked", %{conn: conn, user_id: user_id} do
      # Create app token first
      {:ok, app_token, private_key_pem} =
        JwtTestHelper.create_app_token(user_id, scopes: ["user.sync"])

      # Revoke the app token
      app_token
      |> AppToken.revoke_changeset()
      |> SystemRepo.update!()

      # Generate JWT with the now-revoked app
      jwt = JwtTestHelper.generate_jwt(app_token, private_key_pem)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{jwt}")
        |> post("/api/v1/auth/refresh")

      # The JWTAuth plug rejects revoked tokens before the controller
      response = json_response(conn, 401)
      assert response["error"] == "UNAUTHORIZED"
      assert response["message"] == "Unauthorized"
    end

    test "works with minimal scopes", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.subscriptions.read"])
        |> post("/api/v1/auth/refresh")

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["scopes"] == ["user.subscriptions.read"]
    end
  end
end
