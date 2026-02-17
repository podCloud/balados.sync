defmodule BaladosSyncWeb.CollectionsControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher

  alias BaladosSyncCore.Commands.{
    CreateCollection,
    Subscribe,
    AddFeedToCollection
  }

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Collection, Subscription, CollectionSubscription}
  alias BaladosSyncWeb.JwtTestHelper

  # Helper to insert a collection projection directly (projectors are disabled in test)
  defp insert_collection(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Collection{}
    |> Collection.changeset(
      Map.merge(
        %{
          is_default: false,
          inserted_at: now,
          updated_at: now
        },
        attrs
      )
    )
    |> ProjectionsRepo.insert!()
  end

  # Helper to insert a subscription projection directly
  defp insert_subscription(user_id, feed, rss_source_id \\ "podcast-123") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Subscription{}
    |> Ecto.Changeset.change(%{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_id: rss_source_id,
      subscribed_at: now,
      updated_at: now
    })
    |> ProjectionsRepo.insert!()
  end

  # Helper to create a collection in BOTH the aggregate (event store) and the projection
  defp create_collection_with_aggregate(user_id, title, opts \\ []) do
    collection_id = Ecto.UUID.generate()
    is_default = Keyword.get(opts, :is_default, false)

    # Dispatch command to seed aggregate state
    :ok =
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        collection_id: collection_id,
        title: title,
        is_default: is_default,
        event_infos: %{}
      })

    # Insert matching projection (projectors are disabled in test)
    insert_collection(%{
      id: collection_id,
      user_id: user_id,
      title: title,
      is_default: is_default
    })
  end

  # Helper to subscribe in the aggregate (event store)
  defp subscribe_in_aggregate(user_id, feed) do
    Dispatcher.dispatch(%Subscribe{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_id: "src-#{:erlang.phash2(feed)}",
      subscribed_at: DateTime.utc_now(),
      event_infos: %{}
    })
  end

  setup do
    user_id = Ecto.UUID.generate()
    {:ok, user_id: user_id}
  end

  describe "GET /api/v1/collections" do
    test "lists user's collections", %{conn: conn, user_id: user_id} do
      # Insert collection projection directly
      insert_collection(%{user_id: user_id, title: "News"})

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> get("/api/v1/collections")

      assert response(conn, 200)
      body = json_response(conn, 200)
      assert is_list(body["collections"])
      assert length(body["collections"]) > 0
    end

    test "does not list other users' collections", %{conn: conn, user_id: user_id} do
      other_user_id = Ecto.UUID.generate()

      # Insert collection for other user
      insert_collection(%{user_id: other_user_id, title: "Other News"})

      # Insert collection for current user
      insert_collection(%{user_id: user_id, title: "My News"})

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> get("/api/v1/collections")

      assert response(conn, 200)
      body = json_response(conn, 200)

      # Should only see own collection
      assert Enum.any?(body["collections"], fn c -> c["title"] == "My News" end)
      assert not Enum.any?(body["collections"], fn c -> c["title"] == "Other News" end)
    end
  end

  describe "PATCH /api/v1/collections/:id" do
    test "updates collection title", %{conn: conn, user_id: user_id} do
      # Create collection in both aggregate and projection
      collection = create_collection_with_aggregate(user_id, "News")

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> patch("/api/v1/collections/#{collection.id}", %{"title" => "Breaking News"})

      assert response(conn, 200)
      body = json_response(conn, 200)
      # Projection isn't updated by projector in test, but command succeeds
      assert body["collection"]["id"] == collection.id
    end

    test "returns 404 for non-existent collection", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> patch("/api/v1/collections/00000000-0000-0000-0000-000000000000", %{
          "title" => "New Title"
        })

      assert response(conn, 404)
    end
  end

  describe "DELETE /api/v1/collections/:id" do
    test "deletes a collection", %{conn: conn, user_id: user_id} do
      # Create collection in both aggregate and projection
      collection = create_collection_with_aggregate(user_id, "News")

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> delete("/api/v1/collections/#{collection.id}")

      assert response(conn, 200)
      assert json_response(conn, 200)["status"] == "success"
    end

    test "cannot delete default collection", %{conn: conn, user_id: user_id} do
      # Create default collection in both aggregate and projection
      collection = create_collection_with_aggregate(user_id, "All", is_default: true)

      assert not is_nil(collection)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> delete("/api/v1/collections/#{collection.id}")

      assert response(conn, 403)
      assert json_response(conn, 403)["error"] == "FORBIDDEN"
    end
  end

  describe "POST /api/v1/collections/:id/feeds" do
    test "adds a subscribed feed to collection", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      # Seed aggregate with subscription and collection
      :ok = subscribe_in_aggregate(user_id, feed)
      collection = create_collection_with_aggregate(user_id, "News")

      # Insert subscription projection (for controller's subscription check)
      insert_subscription(user_id, feed)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> post("/api/v1/collections/#{collection.id}/feeds", %{"rss_source_feed" => feed})

      assert response(conn, 200)
      assert json_response(conn, 200)["status"] == "success"
    end

    test "returns error for unsubscribed feed", %{conn: conn, user_id: user_id} do
      collection = insert_collection(%{user_id: user_id, title: "News"})
      unsubscribed_feed = "aHR0cHM6Ly91bnN1YnNjcmliZWQuZXhhbXBsZS5jb20v"

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> post("/api/v1/collections/#{collection.id}/feeds", %{
          "rss_source_feed" => unsubscribed_feed
        })

      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "VALIDATION_ERROR"
    end
  end

  describe "POST /api/v1/collections - input validation" do
    test "returns 400 when title is missing", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> post("/api/v1/collections", %{})

      response = json_response(conn, 400)
      assert response["error"] == "BAD_REQUEST"
    end
  end

  describe "POST /api/v1/collections/:id/feeds - input validation" do
    test "returns 400 when rss_source_feed is missing", %{conn: conn, user_id: user_id} do
      collection = insert_collection(%{user_id: user_id, title: "News"})

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> post("/api/v1/collections/#{collection.id}/feeds", %{})

      response = json_response(conn, 400)
      assert response["error"] == "BAD_REQUEST"
    end
  end

  describe "DELETE /api/v1/collections/:id/feeds/:feed_id" do
    test "removes a feed from collection", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      # Seed aggregate with subscription, collection, and feed-in-collection
      :ok = subscribe_in_aggregate(user_id, feed)
      collection = create_collection_with_aggregate(user_id, "News")

      # Insert subscription projection (middleware validates subscription before dispatch)
      insert_subscription(user_id, feed)

      :ok =
        Dispatcher.dispatch(%AddFeedToCollection{
          user_id: user_id,
          collection_id: collection.id,
          rss_source_feed: feed,
          event_infos: %{}
        })

      # Insert projections for controller reads
      %CollectionSubscription{}
      |> CollectionSubscription.changeset(%{
        collection_id: collection.id,
        rss_source_feed: feed
      })
      |> ProjectionsRepo.insert!()

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id)
        |> delete("/api/v1/collections/#{collection.id}/feeds/#{feed}")

      assert response(conn, 200)
      assert json_response(conn, 200)["status"] == "success"
    end
  end
end
