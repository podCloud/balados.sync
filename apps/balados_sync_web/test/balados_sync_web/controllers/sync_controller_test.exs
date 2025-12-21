defmodule BaladosSyncWeb.SyncControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, RecordPlay, CreatePlaylist}
  alias BaladosSyncWeb.JwtTestHelper

  @moduletag :sync_controller

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

  describe "POST /api/v1/sync - authentication" do
    test "returns 401 without authorization header", %{conn: conn} do
      conn = post(conn, "/api/v1/sync", %{})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 401 with invalid JWT", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 401)["error"] == "Unauthorized"
    end

    test "returns 403 with insufficient scopes", %{conn: conn, user_id: user_id} do
      # Create token with limited scopes (no sync permission)
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.subscriptions.read"])
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 403)["error"] == "Insufficient permissions"
    end

    test "succeeds with user.sync scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 200)["status"] == "success"
    end

    test "succeeds with user scope (parent scope)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user"])
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 200)["status"] == "success"
    end

    test "succeeds with wildcard scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["*"])
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 200)["status"] == "success"
    end
  end

  describe "POST /api/v1/sync - empty sync" do
    test "returns current user data with empty params", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert is_list(response["data"]["subscriptions"])
      assert is_list(response["data"]["play_statuses"])
      assert is_list(response["data"]["playlists"])
    end

    test "returns existing subscriptions", %{conn: conn, user_id: user_id} do
      # Add another subscription
      Dispatcher.dispatch(%Subscribe{
        user_id: user_id,
        rss_source_feed: "aHR0cHM6Ly90ZXN0LmV4YW1wbGUuY29tL2ZlZWQ=",
        rss_source_id: "test-feed",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      })

      # Wait for projection - eventual consistency
      Process.sleep(150)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      # Should have at least 1 subscription (init subscription from setup)
      assert length(response["data"]["subscriptions"]) >= 1
    end
  end

  describe "POST /api/v1/sync - subscription sync" do
    test "accepts new subscription from client and returns success", %{conn: conn, user_id: user_id} do
      new_feed = "aHR0cHM6Ly9uZXcuZXhhbXBsZS5jb20vZmVlZA=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => [
            %{
              "rss_source_feed" => new_feed,
              "rss_source_id" => "new-podcast",
              "subscribed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)

      # Command was accepted and processed
      assert response["status"] == "success"
      # Response includes subscriptions data structure
      assert is_list(response["data"]["subscriptions"])
    end

    test "accepts unsubscribe from client and returns success", %{conn: conn, user_id: user_id} do
      # First subscribe to a feed
      feed = "aHR0cHM6Ly90b3Vuc3Vic2NyaWJlLmV4YW1wbGUuY29t"

      Dispatcher.dispatch(%Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "to-unsubscribe",
        subscribed_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        event_infos: %{}
      })

      Process.sleep(100)

      # Now sync with unsubscribe
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_id" => "to-unsubscribe",
              "subscribed_at" => DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601(),
              "unsubscribed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)

      # Command was accepted and processed
      assert response["status"] == "success"
      # Response includes subscriptions data structure
      assert is_list(response["data"]["subscriptions"])
    end
  end

  describe "POST /api/v1/sync - play status sync" do
    test "syncs play position from client", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9wbGF5LmV4YW1wbGUuY29tL2ZlZWQ="
      item = "aHR0cHM6Ly9wbGF5LmV4YW1wbGUuY29tL2VwaXNvZGUx"

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "play_statuses" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_item" => item,
              "position" => 300,
              "played" => false,
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "syncs played status from client", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9wbGF5ZWQuZXhhbXBsZS5jb20vZmVlZA=="
      item = "aHR0cHM6Ly9wbGF5ZWQuZXhhbXBsZS5jb20vZXBpc29kZTE="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "play_statuses" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_item" => item,
              "position" => 1800,
              "played" => true,
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end

  describe "POST /api/v1/sync - combined sync" do
    test "syncs subscriptions and play statuses together", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9jb21iaW5lZC5leGFtcGxlLmNvbS9mZWVk"
      item = "aHR0cHM6Ly9jb21iaW5lZC5leGFtcGxlLmNvbS9lcGlzb2RlMQ=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_id" => "combined-podcast",
              "subscribed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ],
          "play_statuses" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_item" => item,
              "position" => 600,
              "played" => false,
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert is_list(response["data"]["subscriptions"])
      assert is_list(response["data"]["play_statuses"])
    end
  end

  describe "POST /api/v1/sync - edge cases" do
    test "handles empty arrays gracefully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => [],
          "play_statuses" => [],
          "playlists" => []
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "handles nil values in params", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => nil,
          "play_statuses" => nil
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
    end

    test "handles invalid datetime format gracefully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => [
            %{
              "rss_source_feed" => "aHR0cHM6Ly9iYWRkYXRlLmV4YW1wbGUuY29t",
              "rss_source_id" => "bad-date",
              "subscribed_at" => "not-a-date"
            }
          ]
        })

      # Should still succeed but with nil datetime
      response = json_response(conn, 200)
      assert response["status"] == "success"
    end
  end

  describe "POST /api/v1/sync - response format" do
    test "returns properly formatted subscription data", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      # Check subscription format
      if length(response["data"]["subscriptions"]) > 0 do
        sub = hd(response["data"]["subscriptions"])
        assert Map.has_key?(sub, "rss_source_feed")
        assert Map.has_key?(sub, "rss_source_id")
        assert Map.has_key?(sub, "subscribed_at")
      end
    end

    test "returns properly formatted play status data", %{conn: conn, user_id: user_id} do
      # First record a play
      Dispatcher.dispatch(%RecordPlay{
        user_id: user_id,
        rss_source_feed: "aHR0cHM6Ly9mb3JtYXQuZXhhbXBsZS5jb20vZmVlZA==",
        rss_source_item: "aHR0cHM6Ly9mb3JtYXQuZXhhbXBsZS5jb20vZXBpc29kZTE=",
        position: 500,
        played: false,
        event_infos: %{}
      })

      Process.sleep(50)

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      # Check play status format
      if length(response["data"]["play_statuses"]) > 0 do
        ps = hd(response["data"]["play_statuses"])
        assert Map.has_key?(ps, "rss_source_feed")
        assert Map.has_key?(ps, "rss_source_item")
        assert Map.has_key?(ps, "position")
        assert Map.has_key?(ps, "played")
        assert Map.has_key?(ps, "updated_at")
      end
    end
  end

  describe "POST /api/v1/sync - playlist sync" do
    test "syncs new playlist from client", %{conn: conn, user_id: user_id} do
      playlist_id = Ecto.UUID.generate()

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "playlists" => [
            %{
              "id" => playlist_id,
              "name" => "My Synced Playlist",
              "description" => "A playlist synced from client",
              "is_public" => false,
              "items" => [],
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert is_list(response["data"]["playlists"])

      # Verify playlist was created
      playlists = response["data"]["playlists"]
      synced_playlist = Enum.find(playlists, fn p -> p["id"] == playlist_id end)
      assert synced_playlist["name"] == "My Synced Playlist"
    end

    test "syncs playlist with items from client", %{conn: conn, user_id: user_id} do
      playlist_id = Ecto.UUID.generate()
      feed = "aHR0cHM6Ly9wbGF5bGlzdC5leGFtcGxlLmNvbS9mZWVk"
      item = "aHR0cHM6Ly9wbGF5bGlzdC5leGFtcGxlLmNvbS9lcGlzb2RlMQ=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "playlists" => [
            %{
              "id" => playlist_id,
              "name" => "Playlist With Items",
              "items" => [
                %{
                  "rss_source_feed" => feed,
                  "rss_source_item" => item,
                  "item_title" => "Episode 1",
                  "feed_title" => "My Podcast",
                  "position" => 0
                }
              ],
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"

      # Verify playlist has items
      playlists = response["data"]["playlists"]
      synced_playlist = Enum.find(playlists, fn p -> p["id"] == playlist_id end)
      assert synced_playlist != nil
      assert length(synced_playlist["items"]) == 1
    end

    test "syncs deleted playlist from client", %{conn: conn, user_id: user_id} do
      # First create a playlist via command
      playlist_id = Ecto.UUID.generate()

      Dispatcher.dispatch(%CreatePlaylist{
        user_id: user_id,
        name: "To Be Deleted",
        playlist_id: playlist_id,
        event_infos: %{}
      })

      # Wait for projection to complete (eventual consistency)
      Process.sleep(300)

      # Now sync with deleted_at
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "playlists" => [
            %{
              "id" => playlist_id,
              "name" => "To Be Deleted",
              "deleted_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"

      # Verify playlist is no longer in active list
      playlists = response["data"]["playlists"]
      deleted_playlist = Enum.find(playlists, fn p -> p["id"] == playlist_id end)
      assert deleted_playlist == nil
    end

    test "older client update does not overwrite newer server data", %{conn: conn, user_id: user_id} do
      # Create a playlist directly in projections (server-side data)
      playlist_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # First sync to create the playlist with current timestamp
      conn1 =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "playlists" => [
            %{
              "id" => playlist_id,
              "name" => "Server Playlist",
              "updated_at" => now |> DateTime.to_iso8601()
            }
          ]
        })

      assert json_response(conn1, 200)["status"] == "success"

      # Try to sync with older data (1 hour ago)
      old_time = DateTime.add(now, -3600, :second)

      conn2 =
        build_conn()
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "playlists" => [
            %{
              "id" => playlist_id,
              "name" => "Old Client Name",
              "updated_at" => old_time |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn2, 200)
      assert response["status"] == "success"

      # Server name should be preserved (not overwritten by older client data)
      playlists = response["data"]["playlists"]
      playlist = Enum.find(playlists, fn p -> p["id"] == playlist_id end)
      assert playlist["name"] == "Server Playlist"
    end

    test "handles playlist sync with subscriptions and play statuses", %{conn: conn, user_id: user_id} do
      playlist_id = Ecto.UUID.generate()
      feed = "aHR0cHM6Ly9jb21iaW5lZC5leGFtcGxlLmNvbS9mZWVk"
      item = "aHR0cHM6Ly9jb21iaW5lZC5leGFtcGxlLmNvbS9lcGlzb2RlMQ=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "subscriptions" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_id" => "combined-podcast",
              "subscribed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ],
          "play_statuses" => [
            %{
              "rss_source_feed" => feed,
              "rss_source_item" => item,
              "position" => 600,
              "played" => false,
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ],
          "playlists" => [
            %{
              "id" => playlist_id,
              "name" => "Combined Playlist",
              "items" => [
                %{
                  "rss_source_feed" => feed,
                  "rss_source_item" => item,
                  "position" => 0
                }
              ],
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          ]
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert is_list(response["data"]["subscriptions"])
      assert is_list(response["data"]["play_statuses"])
      assert is_list(response["data"]["playlists"])
    end
  end
end
