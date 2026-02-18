defmodule BaladosSyncWeb.ListeningHistoryExportControllerTest do
  @moduledoc """
  Tests for CSV and JSON export of listening history.
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{PlayStatus, User}

  @feed_url "https://example.com/podcast.xml"

  setup do
    user_id = Ecto.UUID.generate()

    user =
      %User{}
      |> User.registration_changeset(%{
        email: "test-#{System.unique_integer()}@example.com",
        username: "testuser#{System.unique_integer()}",
        password: "TestPassword123!",
        password_confirmation: "TestPassword123!"
      })
      |> Ecto.Changeset.put_change(:id, user_id)
      |> SystemRepo.insert!()

    conn =
      build_conn()
      |> init_test_session(%{"user_token" => user.id, locale: "en"})

    {:ok, conn: conn, user: user}
  end

  describe "export_csv" do
    test "returns CSV with header and entries", %{conn: conn, user: user} do
      create_play_status(user.id, "My Podcast", "Episode 1", 300, false)
      create_play_status(user.id, "My Podcast", "Episode 2", 1800, true)

      conn = get(conn, ~p"/listening-history/export.csv")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "listening-history.csv"

      body = response(conn, 200)
      assert body =~ "Podcast,Episode,Status,Position (seconds),Date"
      assert body =~ "My Podcast"
      assert body =~ "Episode 1"
      assert body =~ "in_progress"
      assert body =~ "Episode 2"
      assert body =~ "completed"
    end

    test "escapes CSV values with commas", %{conn: conn, user: user} do
      create_play_status(user.id, "Podcast, Inc.", "Episode \"1\"", 100, false)

      conn = get(conn, ~p"/listening-history/export.csv")
      body = response(conn, 200)

      # Values with commas/quotes should be quoted
      assert body =~ "\"Podcast, Inc.\""
      assert body =~ "\"Episode \"\"1\"\"\""
    end

    test "returns empty CSV when no data", %{conn: conn} do
      conn = get(conn, ~p"/listening-history/export.csv")

      body = response(conn, 200)
      assert body =~ "Podcast,Episode,Status,Position (seconds),Date"
      # Only header line, no data rows
      lines = String.split(body, "\r\n", trim: true)
      assert length(lines) == 1
    end

    test "applies filter params", %{conn: conn, user: user} do
      create_play_status(user.id, "Podcast A", "Ep A", 100, true)
      create_play_status(user.id, "Podcast B", "Ep B", 200, false)

      conn = get(conn, ~p"/listening-history/export.csv?status=completed")
      body = response(conn, 200)

      assert body =~ "Podcast A"
      refute body =~ "Podcast B"
    end
  end

  describe "export_json" do
    test "returns JSON array of entries", %{conn: conn, user: user} do
      create_play_status(user.id, "My Podcast", "Episode 1", 300, false)

      conn = get(conn, ~p"/listening-history/export.json")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      body = Jason.decode!(response(conn, 200))
      assert is_list(body)
      assert length(body) == 1

      entry = hd(body)
      assert entry["podcast"] == "My Podcast"
      assert entry["episode"] == "Episode 1"
      assert entry["status"] == "in_progress"
      assert entry["position"] == 300
    end

    test "returns empty JSON array when no data", %{conn: conn} do
      conn = get(conn, ~p"/listening-history/export.json")

      body = Jason.decode!(response(conn, 200))
      assert body == []
    end
  end

  describe "authentication" do
    test "redirects unauthenticated users for CSV", %{} do
      conn = build_conn()
      conn = get(conn, ~p"/listening-history/export.csv")

      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "redirects unauthenticated users for JSON", %{} do
      conn = build_conn()
      conn = get(conn, ~p"/listening-history/export.json")

      assert redirected_to(conn) =~ "/users/log_in"
    end
  end

  # Helpers

  defp create_play_status(user_id, feed_title, item_title, position, played) do
    encoded_feed = Base.url_encode64(@feed_url, padding: false)
    encoded_item = Base.url_encode64("#{item_title},#{@feed_url}/ep", padding: false)

    %PlayStatus{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_item: encoded_item,
      rss_feed_title: feed_title,
      rss_item_title: item_title,
      position: position,
      played: played,
      rss_enclosure: %{"duration" => 3600},
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
    |> ProjectionsRepo.insert!()
  end
end
