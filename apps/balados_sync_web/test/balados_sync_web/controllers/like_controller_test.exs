defmodule BaladosSyncWeb.LikeControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.LikePodcast
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserLike
  alias BaladosSyncWeb.JwtTestHelper

  setup do
    user_id = Ecto.UUID.generate()
    {:ok, user_id: user_id}
  end

  describe "POST /api/v1/likes - authentication" do
    test "returns 401 without authorization header", %{conn: conn} do
      conn = post(conn, "/api/v1/likes", %{})
      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "returns 403 with insufficient scopes", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.read"])
        |> post("/api/v1/likes", %{"rss_source_feed" => "dGVzdA"})

      assert json_response(conn, 403)["error"] == "FORBIDDEN"
    end
  end

  describe "POST /api/v1/likes - like podcast" do
    test "returns 400 when rss_source_feed is missing", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.write"])
        |> post("/api/v1/likes", %{})

      response = json_response(conn, 400)
      assert response["error"] == "BAD_REQUEST"
    end

    test "successfully likes a podcast", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.write"])
        |> post("/api/v1/likes", %{"rss_source_feed" => "dGVzdC1mZWVk"})

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "successfully likes an episode", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.write"])
        |> post("/api/v1/likes", %{
          "rss_source_feed" => "dGVzdC1mZWVk",
          "rss_source_item" => "dGVzdC1pdGVt"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end

  describe "DELETE /api/v1/likes/:feed - unlike podcast" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = delete(conn, "/api/v1/likes/dGVzdC1mZWVk")
      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "successfully unlikes a podcast", %{conn: conn, user_id: user_id} do
      # Dispatch command only - unlike dispatches its own command regardless of projection state
      Dispatcher.dispatch(%LikePodcast{
        user_id: user_id,
        rss_source_feed: "dGVzdC1mZWVk",
        liked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        event_infos: %{}
      })

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.write"])
        |> delete("/api/v1/likes/dGVzdC1mZWVk")

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end

  describe "DELETE /api/v1/likes/:feed/:item - unlike episode" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = delete(conn, "/api/v1/likes/dGVzdC1mZWVk/dGVzdC1pdGVt")
      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "successfully unlikes an episode", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.write"])
        |> delete("/api/v1/likes/dGVzdC1mZWVk/dGVzdC1pdGVt")

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end

  describe "GET /api/v1/likes - list likes" do
    test "returns 401 without authorization", %{conn: conn} do
      conn = get(conn, "/api/v1/likes")
      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "returns empty list for user with no likes", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.read"])
        |> get("/api/v1/likes")

      response = json_response(conn, 200)
      assert response["likes"] == []
      assert response["has_more"] == false
    end

    test "returns likes after liking a podcast", %{conn: conn, user_id: user_id} do
      # Insert directly into projections (projectors don't run in test env)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      ProjectionsRepo.insert!(%UserLike{
        user_id: user_id,
        rss_source_feed: "dGVzdC1mZWVk",
        rss_source_item: nil,
        liked_at: now,
        unliked_at: nil
      })

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.read"])
        |> get("/api/v1/likes")

      response = json_response(conn, 200)
      assert length(response["likes"]) == 1
      assert hd(response["likes"])["rss_source_feed"] == "dGVzdC1mZWVk"
      assert response["has_more"] == false
    end

    test "respects limit parameter", %{conn: conn, user_id: user_id} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..3 do
        ProjectionsRepo.insert!(%UserLike{
          user_id: user_id,
          rss_source_feed: "feed-#{i}",
          rss_source_item: nil,
          liked_at: DateTime.add(now, i, :second),
          unliked_at: nil
        })
      end

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes.read"])
        |> get("/api/v1/likes?limit=2")

      response = json_response(conn, 200)
      assert length(response["likes"]) == 2
      assert response["has_more"] == true
    end

    test "works with wildcard scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["*"])
        |> get("/api/v1/likes")

      response = json_response(conn, 200)
      assert response["likes"] == []
      assert response["has_more"] == false
    end

    test "works with parent scope user.likes", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.likes"])
        |> get("/api/v1/likes")

      response = json_response(conn, 200)
      assert response["likes"] == []
      assert response["has_more"] == false
    end
  end
end
