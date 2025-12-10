defmodule BaladosSyncWeb.CollectionsControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.Collection
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, CreateCollection}

  setup do
    # Create a test user and JWT token
    user_id = "test-user-123"
    device_id = "device-456"

    token = generate_jwt_token(user_id, device_id)

    {:ok, user_id: user_id, device_id: device_id, token: token}
  end

  describe "POST /api/v1/collections" do
    test "creates a new collection", %{conn: conn, user_id: user_id, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/collections", %{
          "title" => "News",
          "slug" => "news"
        })

      assert response(conn, :created)
      body = json_response(conn, :created)
      assert body["collection"]["title"] == "News"
      assert body["collection"]["slug"] == "news"
      assert body["collection"]["user_id"] == user_id
      assert is_list(body["collection"]["feeds"])
    end

    test "returns error without required fields", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/collections", %{"title" => "News"})

      assert response(conn, 422)
    end
  end

  describe "GET /api/v1/collections" do
    test "lists user's collections", %{conn: conn, user_id: user_id, token: token} do
      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/collections")

      assert response(conn, 200)
      body = json_response(conn, 200)
      assert is_list(body["collections"])
      # Should have at least the "all" default collection
      assert length(body["collections"]) > 0
    end

    test "does not list other users' collections", %{conn: conn, token: token} do
      other_user_id = "other-user-789"

      # Create collection for other user
      Dispatcher.dispatch(%CreateCollection{
        user_id: other_user_id,
        title: "Other News",
        slug: "other-news",
        event_infos: %{}
      })

      # Create collection for current user
      conn_user_id = extract_user_id_from_token(token)

      Dispatcher.dispatch(%CreateCollection{
        user_id: conn_user_id,
        title: "My News",
        slug: "my-news",
        event_infos: %{}
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/collections")

      assert response(conn, 200)
      body = json_response(conn, 200)

      # Should only see own collection
      assert Enum.any?(body["collections"], fn c -> c["slug"] == "my-news" end)
      assert not Enum.any?(body["collections"], fn c -> c["slug"] == "other-news" end)
    end
  end

  describe "PATCH /api/v1/collections/:id" do
    test "updates collection title", %{conn: conn, user_id: user_id, token: token} do
      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      })

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, slug: "news")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/api/v1/collections/#{collection.id}", %{"title" => "Breaking News"})

      assert response(conn, 200)
      body = json_response(conn, 200)
      assert body["collection"]["title"] == "Breaking News"
    end

    test "returns 404 for non-existent collection", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> patch("/api/v1/collections/00000000-0000-0000-0000-000000000000", %{
          "title" => "New Title"
        })

      assert response(conn, 404)
    end
  end

  describe "DELETE /api/v1/collections/:id" do
    test "deletes a collection", %{conn: conn, user_id: user_id, token: token} do
      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      })

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, slug: "news")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/api/v1/collections/#{collection.id}")

      assert response(conn, 200)
      assert json_response(conn, 200)["status"] == "success"
    end

    test "cannot delete default collection", %{conn: conn, user_id: user_id, token: token} do
      # Get the default "all" collection
      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, slug: "all")

      assert not is_nil(collection)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/api/v1/collections/#{collection.id}")

      assert response(conn, 403)
      assert json_response(conn, 403)["error"] == "cannot_delete_default_collection"
    end
  end

  describe "POST /api/v1/collections/:id/feeds" do
    test "adds a subscribed feed to collection", %{conn: conn, user_id: user_id, token: token} do
      # Subscribe to a feed first
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      Dispatcher.dispatch(%Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      })

      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      })

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, slug: "news")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/collections/#{collection.id}/feeds", %{"rss_source_feed" => feed})

      assert response(conn, 200)
      assert json_response(conn, 200)["status"] == "success"
    end

    test "returns error for unsubscribed feed", %{conn: conn, user_id: user_id, token: token} do
      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      })

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, slug: "news")
      unsubscribed_feed = "aHR0cHM6Ly91bnN1YnNjcmliZWQuZXhhbXBsZS5jb20v"

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/collections/#{collection.id}/feeds", %{
          "rss_source_feed" => unsubscribed_feed
        })

      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "feed_not_subscribed"
    end
  end

  describe "DELETE /api/v1/collections/:id/feeds/:feed_id" do
    test "removes a feed from collection", %{conn: conn, user_id: user_id, token: token} do
      # Subscribe to a feed
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      Dispatcher.dispatch(%Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      })

      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      })

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, slug: "news")

      # Add feed to collection
      Dispatcher.dispatch(%BaladosSyncCore.Commands.AddFeedToCollection{
        user_id: user_id,
        collection_id: collection.id,
        rss_source_feed: feed,
        event_infos: %{}
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete("/api/v1/collections/#{collection.id}/feeds/#{feed}")

      assert response(conn, 200)
      assert json_response(conn, 200)["status"] == "success"
    end
  end

  # Helper functions

  defp generate_jwt_token(user_id, device_id) do
    claims = %{
      "sub" => user_id,
      "device_id" => device_id,
      "device_name" => "Test Device",
      "scope" => "user.* *"
    }

    {:ok, token, _claims} = BaladosSyncWeb.Guardian.encode_and_sign(claims)
    token
  end

  defp extract_user_id_from_token(token) do
    {:ok, claims} = BaladosSyncWeb.Guardian.decode_and_verify(token)
    claims["sub"]
  end
end
