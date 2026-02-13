defmodule BaladosSyncWeb.RssAggregateControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{PlayToken, Collection, Subscription, CollectionSubscription}

  import Ecto.Query

  # Helper to insert a subscription projection directly (projectors disabled in test)
  defp insert_subscription(user_id, feed, rss_source_id \\ "podcast-123") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Subscription{}
    |> Subscription.changeset(%{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_id: rss_source_id,
      subscribed_at: now
    })
    |> ProjectionsRepo.insert!()
  end

  # Helper to insert a collection projection directly
  defp insert_collection(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Collection{}
    |> Collection.changeset(
      Map.merge(
        %{is_default: false, inserted_at: now, updated_at: now},
        attrs
      )
    )
    |> ProjectionsRepo.insert!()
  end

  setup do
    # Create a test user
    user_id = Ecto.UUID.generate()

    # Create a PlayToken for testing
    token = PlayToken.generate_token()

    {:ok, _} =
      SystemRepo.insert(%PlayToken{
        user_id: user_id,
        token: token,
        name: "Test Token",
        expires_at: nil
      })

    # Insert initial subscription projection directly
    insert_subscription(user_id, "aHR0cHM6Ly9kdW1teS5pbml0aWFsaXplci5jb20vZmVlZA", "init-feed")

    {:ok, user_id: user_id, token: token}
  end

  describe "GET /rss/:user_token/subscriptions" do
    test "returns 401 for invalid token", %{conn: conn} do
      conn = get(conn, "/rss/invalid_token/subscriptions")

      assert response(conn, 401)
      assert json_response(conn, 401)["error"] == "Invalid or revoked token"
    end

    test "returns aggregated feed for user subscriptions", %{
      conn: conn,
      user_id: user_id,
      token: token
    } do
      # Insert subscription projection directly
      insert_subscription(user_id, "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q=")

      conn = get(conn, "/rss/#{token}/subscriptions")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> Enum.at(0) =~ "application/xml"
      assert get_resp_header(conn, "cache-control") |> Enum.at(0) =~ "private, max-age=60"

      # Check XML structure
      body = response(conn, 200)
      assert body =~ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      assert body =~ "<rss version=\"2.0\""
      assert body =~ "<title>My Subscriptions</title>"
    end

    test "updates token last_used_at", %{conn: conn, user_id: user_id, token: token} do
      # Insert subscription projection directly
      insert_subscription(user_id, "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q=")

      # Get token before request
      token_before =
        from(t in PlayToken, where: t.token == ^token, select: t.last_used_at)
        |> SystemRepo.one()

      conn = get(conn, "/rss/#{token}/subscriptions")
      assert response(conn, 200)

      # Wait for async update
      Process.sleep(100)

      # Get token after request
      token_after =
        from(t in PlayToken, where: t.token == ^token, select: t.last_used_at)
        |> SystemRepo.one()

      assert token_before != token_after
      assert token_after != nil
    end
  end

  describe "GET /rss/:user_token/collections/:collection_id" do
    test "returns 401 for invalid token", %{conn: conn} do
      collection_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/invalid_token/collections/#{collection_id}")

      assert response(conn, 401)
      assert json_response(conn, 401)["error"] == "Invalid or revoked token"
    end

    test "returns 404 for non-existent collection", %{conn: conn, token: token} do
      collection_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/#{token}/collections/#{collection_id}")

      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "Collection not found"
    end

    test "returns 404 for another user's collection", %{conn: conn, token: token} do
      other_user_id = Ecto.UUID.generate()

      # Insert collection for another user directly
      collection = insert_collection(%{user_id: other_user_id, title: "Other User Collection"})

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}")

      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "Collection not found"
    end

    test "returns aggregated feed for collection subscriptions", %{
      conn: conn,
      user_id: user_id,
      token: token
    } do
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      # Insert subscription and collection projections directly
      insert_subscription(user_id, feed)
      collection = insert_collection(%{user_id: user_id, title: "News Collection"})

      # Add feed to collection
      %CollectionSubscription{}
      |> CollectionSubscription.changeset(%{
        collection_id: collection.id,
        rss_source_feed: feed
      })
      |> ProjectionsRepo.insert!()

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> Enum.at(0) =~ "application/xml"
      assert get_resp_header(conn, "cache-control") |> Enum.at(0) =~ "private, max-age=60"

      # Check XML structure
      body = response(conn, 200)
      assert body =~ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      assert body =~ "<rss version=\"2.0\""
      assert body =~ "<title>News Collection</title>"
    end

    test "uses collection description in feed", %{
      conn: conn,
      user_id: user_id,
      token: token
    } do
      # Insert collection with description directly
      collection =
        insert_collection(%{
          user_id: user_id,
          title: "Tech News",
          description: "Latest technology news and updates"
        })

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}")

      assert response(conn, 200)

      body = response(conn, 200)
      assert body =~ "<description>Latest technology news and updates</description>"
    end

    test "updates token last_used_at", %{conn: conn, user_id: user_id, token: token} do
      # Insert collection directly
      collection = insert_collection(%{user_id: user_id, title: "Test Collection"})

      # Get token before request
      token_before =
        from(t in PlayToken, where: t.token == ^token, select: t.last_used_at)
        |> SystemRepo.one()

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}")
      assert response(conn, 200)

      # Wait for async update
      Process.sleep(100)

      # Get token after request
      token_after =
        from(t in PlayToken, where: t.token == ^token, select: t.last_used_at)
        |> SystemRepo.one()

      assert token_before != token_after
      assert token_after != nil
    end
  end

  describe "GET /rss/:user_token/playlists/:playlist_id" do
    test "returns 401 for invalid token", %{conn: conn} do
      playlist_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/invalid_token/playlists/#{playlist_id}")

      assert response(conn, 401)
      assert json_response(conn, 401)["error"] == "Invalid or revoked token"
    end

    test "returns 404 for non-existent playlist", %{conn: conn, token: token} do
      playlist_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/#{token}/playlists/#{playlist_id}")

      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "Playlist not found"
    end
  end
end
