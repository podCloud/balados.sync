defmodule BaladosSyncWeb.EpisodeControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncWeb.JwtTestHelper

  @moduletag :episode_controller

  setup do
    user_id = Ecto.UUID.generate()

    # Initialize user aggregate with a subscription
    Dispatcher.dispatch(%Subscribe{
      user_id: user_id,
      rss_source_feed: "aHR0cHM6Ly9pbml0LmV4YW1wbGUuY29tL2ZlZWQ",
      rss_source_id: "init-feed",
      subscribed_at: DateTime.utc_now(),
      event_infos: %{}
    })

    Process.sleep(50)

    {:ok, user_id: user_id}
  end

  describe "POST /api/v1/episodes/:item/save - authentication" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = post(conn, "/api/v1/episodes/dGVzdC1pdGVt/save")

      response = json_response(conn, 401)
      assert response["error"] == "UNAUTHORIZED"
      assert response["message"] == "Unauthorized"
    end

    test "returns 401 with invalid JWT", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> post("/api/v1/episodes/dGVzdC1pdGVt/save")

      response = json_response(conn, 401)
      assert response["error"] == "UNAUTHORIZED"
    end

    test "returns 403 with insufficient scope (read-only)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> post("/api/v1/episodes/dGVzdC1pdGVt/save")

      response = json_response(conn, 403)
      assert response["error"] == "FORBIDDEN"
    end
  end

  describe "POST /api/v1/episodes/:item/save - functionality" do
    test "saves an episode successfully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/episodes/dGVzdC1pdGVt/save", %{
          "feed" => "aHR0cHM6Ly9pbml0LmV4YW1wbGUuY29tL2ZlZWQ"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "saves an episode without feed parameter", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/episodes/dGVzdC1pdGVt/save", %{})

      # Should still work (feed is optional)
      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end

  describe "POST /api/v1/episodes/:item/share - authentication" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = post(conn, "/api/v1/episodes/dGVzdC1pdGVt/share")

      response = json_response(conn, 401)
      assert response["error"] == "UNAUTHORIZED"
    end

    test "returns 403 with insufficient scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.read"])
        |> post("/api/v1/episodes/dGVzdC1pdGVt/share")

      response = json_response(conn, 403)
      assert response["error"] == "FORBIDDEN"
    end
  end

  describe "POST /api/v1/episodes/:item/share - functionality" do
    test "shares an episode successfully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.plays.write"])
        |> post("/api/v1/episodes/dGVzdC1pdGVt/share", %{
          "feed" => "aHR0cHM6Ly9pbml0LmV4YW1wbGUuY29tL2ZlZWQ"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end
end
