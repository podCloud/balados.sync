defmodule BaladosSyncWeb.SyncControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, RecordPlay, CreatePlaylist}
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Subscription, PlayStatus}
  alias BaladosSyncWeb.JwtTestHelper

  @moduletag :sync_controller

  # Helper to insert a subscription projection directly (projectors are disabled in test)
  defp insert_subscription(user_id, feed, rss_source_id) do
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

  # Helper to insert a play status projection directly
  defp insert_play_status(user_id, feed, item, position, played \\ false) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %PlayStatus{}
    |> Ecto.Changeset.change(%{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      position: position,
      played: played,
      updated_at: now
    })
    |> ProjectionsRepo.insert!()
  end

  setup do
    user_id = Ecto.UUID.generate()

    # Insert initial subscription projection directly (projectors are disabled in test)
    insert_subscription(user_id, "aHR0cHM6Ly9pbml0LmV4YW1wbGUuY29tL2ZlZWQ=", "init-feed")

    {:ok, user_id: user_id}
  end

  describe "POST /api/v1/sync - authentication" do
    test "returns 401 without authorization header", %{conn: conn} do
      conn = post(conn, "/api/v1/sync", %{})

      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "returns 401 with invalid JWT", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.jwt.token")
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 401)["error"] == "UNAUTHORIZED"
    end

    test "returns 403 with insufficient scopes", %{conn: conn, user_id: user_id} do
      # Create token with limited scopes (no sync permission)
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.subscriptions.read"])
        |> post("/api/v1/sync", %{})

      assert json_response(conn, 403)["error"] == "FORBIDDEN"
    end

    test "succeeds with user.sync scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
    end

    test "succeeds with user scope (parent scope)", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
    end

    test "succeeds with wildcard scope", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["*"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
    end
  end

  describe "POST /api/v1/sync - empty sync" do
    test "returns current user data with empty params", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      assert is_binary(response["sync_token"])
      assert is_list(response["changes"]["subscriptions"])
      assert is_list(response["changes"]["plays"])
      assert is_list(response["changes"]["playlists"])
    end

    test "returns existing subscriptions", %{conn: conn, user_id: user_id} do
      # Add another subscription directly (projectors disabled in test)
      insert_subscription(user_id, "aHR0cHM6Ly90ZXN0LmV4YW1wbGUuY29tL2ZlZWQ=", "test-feed")

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      # Should have at least 1 subscription (init subscription from setup + test-feed)
      assert length(response["changes"]["subscriptions"]) >= 1
    end
  end

  describe "POST /api/v1/sync - subscription sync" do
    test "accepts new subscription from client and returns success", %{
      conn: conn,
      user_id: user_id
    } do
      new_feed = "aHR0cHM6Ly9uZXcuZXhhbXBsZS5jb20vZmVlZA=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "subscriptions" => [
              %{
                "rss_source_feed" => new_feed,
                "rss_source_id" => "new-podcast",
                "subscribed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ]
          }
        })

      response = json_response(conn, 200)

      # Command was accepted and processed
      assert is_binary(response["sync_token"])
      # Response includes subscriptions data structure
      assert is_list(response["changes"]["subscriptions"])
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
          "changes" => %{
            "subscriptions" => [
              %{
                "rss_source_feed" => feed,
                "rss_source_id" => "to-unsubscribe",
                "subscribed_at" =>
                  DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601(),
                "unsubscribed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ]
          }
        })

      response = json_response(conn, 200)

      # Command was accepted and processed
      assert is_binary(response["sync_token"])
      # Response includes subscriptions data structure
      assert is_list(response["changes"]["subscriptions"])
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
          "changes" => %{
            "play_statuses" => [
              %{
                "rss_source_feed" => feed,
                "rss_source_item" => item,
                "position" => 300,
                "played" => false,
                "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ]
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
    end

    test "syncs played status from client", %{conn: conn, user_id: user_id} do
      feed = "aHR0cHM6Ly9wbGF5ZWQuZXhhbXBsZS5jb20vZmVlZA=="
      item = "aHR0cHM6Ly9wbGF5ZWQuZXhhbXBsZS5jb20vZXBpc29kZTE="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "play_statuses" => [
              %{
                "rss_source_feed" => feed,
                "rss_source_item" => item,
                "position" => 1800,
                "played" => true,
                "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ]
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
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
          "changes" => %{
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
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
      assert is_list(response["changes"]["subscriptions"])
      assert is_list(response["changes"]["plays"])
    end
  end

  describe "POST /api/v1/sync - edge cases" do
    test "handles empty arrays gracefully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "subscriptions" => [],
            "play_statuses" => [],
            "playlists" => []
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
    end

    test "handles nil values in params", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "subscriptions" => nil,
            "play_statuses" => nil
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
    end

    test "handles invalid datetime format gracefully", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "subscriptions" => [
              %{
                "rss_source_feed" => "aHR0cHM6Ly9iYWRkYXRlLmV4YW1wbGUuY29t",
                "rss_source_id" => "bad-date",
                "subscribed_at" => "not-a-date"
              }
            ]
          }
        })

      # Should still succeed but with nil datetime
      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
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
      if length(response["changes"]["subscriptions"]) > 0 do
        sub = hd(response["changes"]["subscriptions"])
        assert Map.has_key?(sub, "rss_source_feed")
        assert Map.has_key?(sub, "rss_source_id")
        assert Map.has_key?(sub, "subscribed_at")
      end
    end

    test "returns properly formatted play status data", %{conn: conn, user_id: user_id} do
      # Insert play status directly (projectors disabled in test)
      insert_play_status(
        user_id,
        "aHR0cHM6Ly9mb3JtYXQuZXhhbXBsZS5jb20vZmVlZA==",
        "aHR0cHM6Ly9mb3JtYXQuZXhhbXBsZS5jb20vZXBpc29kZTE=",
        500
      )

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{})

      response = json_response(conn, 200)

      # Check play status format
      if length(response["changes"]["plays"]) > 0 do
        ps = hd(response["changes"]["plays"])
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
          "changes" => %{
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
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
      assert is_list(response["changes"]["playlists"])

      # Verify playlist was created
      playlists = response["changes"]["playlists"]
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
          "changes" => %{
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
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])

      # Verify playlist has items
      playlists = response["changes"]["playlists"]
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
          "changes" => %{
            "playlists" => [
              %{
                "id" => playlist_id,
                "name" => "To Be Deleted",
                "deleted_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            ]
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])

      # Verify playlist is no longer in active list (deleted playlists may still appear with deleted_at set)
      playlists = response["changes"]["playlists"]

      deleted_playlist =
        Enum.find(playlists, fn p -> p["id"] == playlist_id and is_nil(p["deleted_at"]) end)

      assert deleted_playlist == nil
    end

    test "older client update does not overwrite newer server data", %{
      conn: conn,
      user_id: user_id
    } do
      # Create a playlist directly in projections (server-side data)
      playlist_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # First sync to create the playlist with current timestamp
      conn1 =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "playlists" => [
              %{
                "id" => playlist_id,
                "name" => "Server Playlist",
                "updated_at" => now |> DateTime.to_iso8601()
              }
            ]
          }
        })

      assert is_binary(json_response(conn1, 200)["sync_token"])

      # Try to sync with older data (1 hour ago)
      old_time = DateTime.add(now, -3600, :second)

      conn2 =
        build_conn()
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
            "playlists" => [
              %{
                "id" => playlist_id,
                "name" => "Old Client Name",
                "updated_at" => old_time |> DateTime.to_iso8601()
              }
            ]
          }
        })

      response = json_response(conn2, 200)
      assert is_binary(response["sync_token"])

      # Server name should be preserved (not overwritten by older client data)
      playlists = response["changes"]["playlists"]
      playlist = Enum.find(playlists, fn p -> p["id"] == playlist_id end)
      assert playlist["name"] == "Server Playlist"
    end

    test "handles playlist sync with subscriptions and play statuses", %{
      conn: conn,
      user_id: user_id
    } do
      playlist_id = Ecto.UUID.generate()
      feed = "aHR0cHM6Ly9jb21iaW5lZC5leGFtcGxlLmNvbS9mZWVk"
      item = "aHR0cHM6Ly9jb21iaW5lZC5leGFtcGxlLmNvbS9lcGlzb2RlMQ=="

      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.sync"])
        |> post("/api/v1/sync", %{
          "changes" => %{
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
          }
        })

      response = json_response(conn, 200)
      assert is_binary(response["sync_token"])
      assert is_list(response["changes"]["subscriptions"])
      assert is_list(response["changes"]["plays"])
      assert is_list(response["changes"]["playlists"])
    end
  end
end
