defmodule BaladosSyncWeb.RssAggregateControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, CreateCollection, AddFeedToCollection}
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{PlayToken, Collection}

  import Ecto.Query

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

    {:ok, user_id: user_id, token: token}
  end

  describe "GET /rss/:user_token/subscriptions.xml" do
    test "returns 401 for invalid token", %{conn: conn} do
      conn = get(conn, "/rss/invalid_token/subscriptions.xml")

      assert response(conn, 401)
      assert json_response(conn, 401)["error"] == "Invalid or revoked token"
    end

    test "returns aggregated feed for user subscriptions", %{
      conn: conn,
      user_id: user_id,
      token: token
    } do
      # Subscribe to a feed
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      Dispatcher.dispatch(%Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      })

      # Wait for projection
      Process.sleep(100)

      conn = get(conn, "/rss/#{token}/subscriptions.xml")

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
      # Subscribe to a feed
      feed = "aHR0cHM6Ly9mZWVkLmV4YW1wbGUuY29tL3BvZGNhc3Q="

      Dispatcher.dispatch(%Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      })

      # Wait for projection
      Process.sleep(100)

      # Get token before request
      token_before =
        from(t in PlayToken, where: t.token == ^token, select: t.last_used_at)
        |> SystemRepo.one()

      conn = get(conn, "/rss/#{token}/subscriptions.xml")
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

  describe "GET /rss/:user_token/collections/:collection_id.xml" do
    test "returns 401 for invalid token", %{conn: conn} do
      collection_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/invalid_token/collections/#{collection_id}.xml")

      assert response(conn, 401)
      assert json_response(conn, 401)["error"] == "Invalid or revoked token"
    end

    test "returns 404 for non-existent collection", %{conn: conn, token: token} do
      collection_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/#{token}/collections/#{collection_id}.xml")

      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "Collection not found"
    end

    test "returns 404 for another user's collection", %{conn: conn, token: token} do
      other_user_id = Ecto.UUID.generate()

      # Create collection for another user
      Dispatcher.dispatch(%CreateCollection{
        user_id: other_user_id,
        title: "Other User Collection",
        is_default: false,
        event_infos: %{}
      })

      # Wait for projection
      Process.sleep(100)

      collection =
        ProjectionsRepo.get_by(Collection, user_id: other_user_id, title: "Other User Collection")

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}.xml")

      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "Collection not found"
    end

    test "returns aggregated feed for collection subscriptions", %{
      conn: conn,
      user_id: user_id,
      token: token
    } do
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
        title: "News Collection",
        is_default: false,
        event_infos: %{}
      })

      # Wait for projections
      Process.sleep(100)

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, title: "News Collection")

      # Add feed to collection
      Dispatcher.dispatch(%AddFeedToCollection{
        user_id: user_id,
        collection_id: collection.id,
        rss_source_feed: feed,
        event_infos: %{}
      })

      # Wait for projection
      Process.sleep(100)

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}.xml")

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
      # Create a collection with description
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "Tech News",
        description: "Latest technology news and updates",
        is_default: false,
        event_infos: %{}
      })

      # Wait for projection
      Process.sleep(100)

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, title: "Tech News")

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}.xml")

      assert response(conn, 200)

      body = response(conn, 200)
      assert body =~ "<description>Latest technology news and updates</description>"
    end

    test "updates token last_used_at", %{conn: conn, user_id: user_id, token: token} do
      # Create a collection
      Dispatcher.dispatch(%CreateCollection{
        user_id: user_id,
        title: "Test Collection",
        is_default: false,
        event_infos: %{}
      })

      # Wait for projection
      Process.sleep(100)

      collection = ProjectionsRepo.get_by(Collection, user_id: user_id, title: "Test Collection")

      # Get token before request
      token_before =
        from(t in PlayToken, where: t.token == ^token, select: t.last_used_at)
        |> SystemRepo.one()

      conn = get(conn, "/rss/#{token}/collections/#{collection.id}.xml")
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

  describe "GET /rss/:user_token/playlists/:playlist_id.xml" do
    test "returns 401 for invalid token", %{conn: conn} do
      playlist_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/invalid_token/playlists/#{playlist_id}.xml")

      assert response(conn, 401)
      assert json_response(conn, 401)["error"] == "Invalid or revoked token"
    end

    test "returns 404 for non-existent playlist", %{conn: conn, token: token} do
      playlist_id = Ecto.UUID.generate()
      conn = get(conn, "/rss/#{token}/playlists/#{playlist_id}.xml")

      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "Playlist not found"
    end
  end
end
