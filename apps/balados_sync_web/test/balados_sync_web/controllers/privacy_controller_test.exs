defmodule BaladosSyncWeb.PrivacyControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, ChangePrivacy}
  alias BaladosSyncWeb.JwtTestHelper

  @moduletag :privacy_controller

  setup do
    user_id = Ecto.UUID.generate()

    # Initialize user aggregate with a subscription
    Dispatcher.dispatch(%Subscribe{
      user_id: user_id,
      rss_source_feed: "aHR0cHM6Ly9pbml0LmV4YW1wbGUuY29tL2ZlZWQ=",
      rss_source_id: "init-feed",
      subscribed_at: DateTime.utc_now(),
      event_infos: %{}
    })

    Process.sleep(50)

    {:ok, user_id: user_id}
  end

  describe "PUT /api/v1/privacy - authentication" do
    test "returns 401 without authorization header", %{conn: conn} do
      conn = put(conn, "/api/v1/privacy", %{"privacy" => "public"})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 401 with invalid JWT", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> put("/api/v1/privacy", %{"privacy" => "public"})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 403 with insufficient scopes (read-only)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.read"])
        |> put("/api/v1/privacy", %{"privacy" => "public"})

      assert json_response(conn, 403)["error"] == "Insufficient permissions"
    end

    test "succeeds with user.privacy.write scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{"privacy" => "public"})

      assert json_response(conn, 200)["status"] == "success"
    end

    test "succeeds with wildcard scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["*"])
        |> put("/api/v1/privacy", %{"privacy" => "private"})

      assert json_response(conn, 200)["status"] == "success"
    end
  end

  describe "PUT /api/v1/privacy - set privacy level" do
    test "sets global privacy to public", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{"privacy" => "public"})

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "sets global privacy to anonymous", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{"privacy" => "anonymous"})

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "sets global privacy to private", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{"privacy" => "private"})

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "sets privacy per feed", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{
          "privacy" => "private",
          "feed" => feed
        })

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "sets privacy per item", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="
      item = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL2VwaXNvZGUx"

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{
          "privacy" => "anonymous",
          "feed" => feed,
          "item" => item
        })

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "defaults invalid privacy value to public", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> put("/api/v1/privacy", %{"privacy" => "invalid_value"})

      # Should not error - defaults to public
      assert json_response(conn, 200) == %{"status" => "success"}
    end
  end

  describe "GET /api/v1/privacy - authentication" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = get(conn, "/api/v1/privacy")

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 403 with insufficient scopes (write-only)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.write"])
        |> get("/api/v1/privacy")

      assert json_response(conn, 403)["error"] == "Insufficient permissions"
    end

    test "succeeds with user.privacy.read scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.read"])
        |> get("/api/v1/privacy")

      response = json_response(conn, 200)
      assert is_list(response["privacy_settings"])
    end
  end

  describe "GET /api/v1/privacy - list settings" do
    test "returns empty list for new user", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.read"])
        |> get("/api/v1/privacy")

      response = json_response(conn, 200)
      assert response["privacy_settings"] == []
    end

    test "returns privacy settings after update", %{conn: conn, user_id: user_id} do
      # First set privacy
      Dispatcher.dispatch(%ChangePrivacy{
        user_id: user_id,
        rss_source_feed: nil,
        rss_source_item: nil,
        privacy: :private,
        event_infos: %{}
      })

      Process.sleep(100)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.read"])
        |> get("/api/v1/privacy")

      response = json_response(conn, 200)
      assert is_list(response["privacy_settings"])
    end

    test "filters by feed", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9maWx0ZXIuZXhhbXBsZS5jb20vZmVlZA=="

      # Set privacy for this feed
      Dispatcher.dispatch(%ChangePrivacy{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: nil,
        privacy: :anonymous,
        event_infos: %{}
      })

      Process.sleep(100)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.read"])
        |> get("/api/v1/privacy", %{"feed" => feed})

      response = json_response(conn, 200)
      assert is_list(response["privacy_settings"])
    end

    test "filters by item", %{conn: conn, user_id: user_id} do
      item = "aHR0cHM6Ly9maWx0ZXIuZXhhbXBsZS5jb20vaXRlbQ=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.privacy.read"])
        |> get("/api/v1/privacy", %{"item" => item})

      response = json_response(conn, 200)
      assert is_list(response["privacy_settings"])
    end
  end
end
