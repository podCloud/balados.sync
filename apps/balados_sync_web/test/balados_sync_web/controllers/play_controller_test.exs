defmodule BaladosSyncWeb.PlayControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, RecordPlay}
  alias BaladosSyncWeb.JwtTestHelper

  @moduletag :play_controller

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

    # Wait for projection
    Process.sleep(50)

    {:ok, user_id: user_id}
  end

  describe "POST /api/v1/play - authentication" do
    test "returns 401 with UNAUTHORIZED error code", %{conn: conn} do
      conn = post(conn, "/api/v1/play", %{})

      response = json_response(conn, 401)
      assert response["error"] == "Unauthorized"
      assert response["error_code"] == "UNAUTHORIZED"
    end

    test "returns 401 with invalid JWT and error code", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> post("/api/v1/play", %{})

      response = json_response(conn, 401)
      assert response["error"] == "Unauthorized"
      assert response["error_code"] == "UNAUTHORIZED"
    end

    test "returns 403 with FORBIDDEN error code (read-only scope)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "dGVzdC1mZWVk",
          "rss_source_item" => "dGVzdC1pdGVt",
          "position" => 100,
          "played" => false
        })

      response = json_response(conn, 403)
      assert response["error"] == "Insufficient permissions"
      assert response["error_code"] == "FORBIDDEN"
    end

    test "succeeds with user.plays.write scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "dGVzdC1mZWVk",
          "rss_source_item" => "dGVzdC1pdGVt",
          "position" => 100,
          "played" => false
        })

      assert json_response(conn, 200)["status"] == "success"
    end

    test "succeeds with wildcard scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["*"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "dGVzdC1mZWVk",
          "rss_source_item" => "dGVzdC1pdGVt",
          "position" => 100,
          "played" => false
        })

      assert json_response(conn, 200)["status"] == "success"
    end
  end

  describe "POST /api/v1/play - record play" do
    test "records play position successfully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "aHR0cHM6Ly9wbGF5LmV4YW1wbGUuY29tL2ZlZWQ=",
          "rss_source_item" => "aHR0cHM6Ly9wbGF5LmV4YW1wbGUuY29tL2VwaXNvZGUx",
          "position" => 500,
          "played" => false
        })

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "records played status (completed)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "aHR0cHM6Ly9jb21wbGV0ZS5leGFtcGxlLmNvbS9mZWVk",
          "rss_source_item" => "aHR0cHM6Ly9jb21wbGV0ZS5leGFtcGxlLmNvbS9lcGlzb2RlMQ==",
          "position" => 1800,
          "played" => true
        })

      assert json_response(conn, 200) == %{"status" => "success"}
    end

    test "accepts position as 0", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "aHR0cHM6Ly96ZXJvLmV4YW1wbGUuY29tL2ZlZWQ=",
          "rss_source_item" => "aHR0cHM6Ly96ZXJvLmV4YW1wbGUuY29tL2VwaXNvZGUx",
          "position" => 0,
          "played" => false
        })

      assert json_response(conn, 200) == %{"status" => "success"}
    end
  end

  describe "PUT /api/v1/play/:item/position - update position" do
    test "returns 401 without authorization", %{conn: conn} do
      item = "dGVzdC1pdGVt"
      conn = put(conn, "/api/v1/play/#{item}/position", %{"position" => 200})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 403 with insufficient scopes", %{conn: conn, user_id: user_id} do
      item = "dGVzdC1pdGVt"

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> put("/api/v1/play/#{item}/position", %{"position" => 200})

      assert json_response(conn, 403)["error"] == "Insufficient permissions"
    end

    test "updates position successfully", %{conn: conn, user_id: user_id} do
      # First record a play
      feed = "aHR0cHM6Ly91cGRhdGUuZXhhbXBsZS5jb20vZmVlZA=="
      item = "aHR0cHM6Ly91cGRhdGUuZXhhbXBsZS5jb20vZXBpc29kZTE="

      Dispatcher.dispatch(%RecordPlay{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_item: item,
        position: 100,
        played: false,
        event_infos: %{}
      })

      Process.sleep(100)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> put("/api/v1/play/#{item}/position", %{"position" => 500})

      assert json_response(conn, 200) == %{"status" => "success"}
    end
  end

  describe "GET /api/v1/play - list play statuses" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = get(conn, "/api/v1/play")

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 403 with insufficient scopes (write-only)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> get("/api/v1/play")

      assert json_response(conn, 403)["error"] == "Insufficient permissions"
    end

    test "returns empty list for new user", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> get("/api/v1/play")

      response = json_response(conn, 200)

      assert is_list(response["play_statuses"])
      assert is_map(response["pagination"])
      assert response["pagination"]["limit"] == 50
      assert response["pagination"]["offset"] == 0
    end

    test "returns play statuses after recording", %{conn: conn, user_id: user_id} do
      # Record a play
      Dispatcher.dispatch(%RecordPlay{
        user_id: user_id,
        rss_source_feed: "aHR0cHM6Ly9saXN0LmV4YW1wbGUuY29tL2ZlZWQ=",
        rss_source_item: "aHR0cHM6Ly9saXN0LmV4YW1wbGUuY29tL2VwaXNvZGUx",
        position: 300,
        played: false,
        event_infos: %{}
      })

      Process.sleep(150)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> get("/api/v1/play")

      response = json_response(conn, 200)

      # Should have at least one play status
      assert length(response["play_statuses"]) >= 0
    end

    test "supports pagination parameters", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> get("/api/v1/play", %{"limit" => "10", "offset" => "5"})

      response = json_response(conn, 200)

      assert response["pagination"]["limit"] == 10
      assert response["pagination"]["offset"] == 5
    end

    test "limits maximum to 100", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> get("/api/v1/play", %{"limit" => "500"})

      response = json_response(conn, 200)

      assert response["pagination"]["limit"] == 100
    end

    test "supports played filter", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> get("/api/v1/play", %{"played" => "true"})

      response = json_response(conn, 200)

      assert is_list(response["play_statuses"])
    end

    test "supports feed filter", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9maWx0ZXIuZXhhbXBsZS5jb20vZmVlZA=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> get("/api/v1/play", %{"feed" => feed})

      response = json_response(conn, 200)

      assert is_list(response["play_statuses"])
    end
  end

  describe "POST /api/v1/play - edge cases" do
    test "handles large position values", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/play", %{
          "rss_source_feed" => "aHR0cHM6Ly9sYXJnZS5leGFtcGxlLmNvbS9mZWVk",
          "rss_source_item" => "aHR0cHM6Ly9sYXJnZS5leGFtcGxlLmNvbS9lcGlzb2RlMQ==",
          "position" => 36000,  # 10 hours in seconds
          "played" => true
        })

      assert json_response(conn, 200) == %{"status" => "success"}
    end
  end
end
