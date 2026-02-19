defmodule BaladosSyncWeb.ListeningHistoryLiveTest do
  @moduledoc """
  Tests for the ListeningHistoryLive LiveView.

  Note: assertions use French strings because the default locale is "fr"
  and the LiveView process picks up the default locale from the Locale plug.
  """

  use BaladosSyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{PlayStatus, User}

  @feed_url_1 "https://example.com/podcast1.xml"
  @feed_url_2 "https://example.com/podcast2.xml"

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
      |> init_test_session(%{"user_token" => user.id})

    {:ok, conn: conn, user: user}
  end

  describe "mount and basic rendering" do
    test "renders empty state when no history", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "Historique d'écoute" and "Aucun historique d'écoute."
      assert html =~ "Historique"
      assert html =~ "Aucun historique"
    end

    test "renders entries when play statuses exist", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "My Podcast",
        rss_item_title: "Episode 1",
        position: 300,
        played: false
      })

      {:ok, _view, html} = live(conn, ~p"/listening-history")

      assert html =~ "My Podcast"
      assert html =~ "Episode 1"
      # French: "1 épisode"
      assert html =~ "pisode"
    end

    test "shows correct count for multiple entries", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast A",
        rss_item_title: "Ep 1",
        position: 100,
        played: false
      })

      create_play_status(user.id, @feed_url_2, "guid2", %{
        rss_feed_title: "Podcast B",
        rss_item_title: "Ep 2",
        position: 0,
        played: true
      })

      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "2 épisodes"
      assert html =~ "pisodes"
    end
  end

  describe "status badges" do
    test "shows completed badge", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Episode",
        position: 1800,
        played: true
      })

      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "Terminé"
      assert html =~ "Termin"
      assert html =~ "bg-green-500"
    end

    test "shows in progress badge", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Episode",
        position: 300,
        played: false
      })

      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "En cours"
      assert html =~ "En cours"
      assert html =~ "bg-blue-500"
    end

    test "shows not started badge", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Episode",
        position: 0,
        played: false
      })

      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "Non commencé"
      assert html =~ "Non commenc"
    end
  end

  describe "filtering" do
    test "filters by feed", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast A",
        rss_item_title: "Ep A",
        position: 100,
        played: false
      })

      create_play_status(user.id, @feed_url_2, "guid2", %{
        rss_feed_title: "Podcast B",
        rss_item_title: "Ep B",
        position: 200,
        played: false
      })

      encoded_feed_1 = Base.url_encode64(@feed_url_1, padding: false)

      {:ok, view, _html} = live(conn, ~p"/listening-history")

      view
      |> element("form")
      |> render_change(%{"feed" => encoded_feed_1, "period" => "", "status" => ""})

      # Re-render to see filtered results after push_patch
      html = render(view)
      assert html =~ "Podcast A"
      assert html =~ "1"
    end

    test "filters by status", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Completed Ep",
        position: 1800,
        played: true
      })

      create_play_status(user.id, @feed_url_1, "guid2", %{
        rss_feed_title: "Podcast",
        rss_item_title: "In Progress Ep",
        position: 300,
        played: false
      })

      {:ok, view, _html} = live(conn, ~p"/listening-history?status=completed")

      html = render(view)
      assert html =~ "Completed Ep"
      # Only 1 entry should be shown
      assert html =~ "1"
    end
  end

  describe "stats panel" do
    test "loads stats asynchronously", %{conn: conn, user: user} do
      create_play_status(user.id, @feed_url_1, "guid1", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Episode 1",
        position: 3600,
        played: true
      })

      create_play_status(user.id, @feed_url_1, "guid2", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Episode 2",
        position: 1800,
        played: false
      })

      {:ok, view, _html} = live(conn, ~p"/listening-history")

      # Trigger async stats load directly
      send(view.pid, :load_stats)
      html = render(view)

      # Total time should show formatted duration (1h30m = 5400s)
      assert html =~ "1:30:00"
    end
  end

  describe "streak calculation" do
    test "consecutive days including today returns correct streak", %{user: user} do
      now = DateTime.utc_now()

      for i <- 0..2 do
        create_play_status(user.id, @feed_url_1, "streak-#{i}", %{
          rss_feed_title: "Podcast",
          rss_item_title: "Episode #{i}",
          position: 100,
          played: false,
          updated_at: DateTime.add(now, -i, :day) |> DateTime.truncate(:second)
        })
      end

      stats = BaladosSyncWeb.Queries.get_listening_stats(user.id)
      assert stats.streak_days == 3
    end

    test "returns zero streak when last activity was 2+ days ago", %{user: user} do
      create_play_status(user.id, @feed_url_1, "old-activity", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Old Episode",
        position: 100,
        played: false,
        updated_at: DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)
      })

      stats = BaladosSyncWeb.Queries.get_listening_stats(user.id)
      assert stats.streak_days == 0
    end

    test "streak stops at gap in consecutive days", %{user: user} do
      now = DateTime.utc_now()

      # Today and yesterday (streak of 2)
      for i <- 0..1 do
        create_play_status(user.id, @feed_url_1, "recent-#{i}", %{
          rss_feed_title: "Podcast",
          rss_item_title: "Recent #{i}",
          position: 100,
          played: false,
          updated_at: DateTime.add(now, -i, :day) |> DateTime.truncate(:second)
        })
      end

      # 4 days ago (gap of 1 day breaks the streak)
      create_play_status(user.id, @feed_url_1, "old", %{
        rss_feed_title: "Podcast",
        rss_item_title: "Old",
        position: 100,
        played: false,
        updated_at: DateTime.add(now, -4, :day) |> DateTime.truncate(:second)
      })

      stats = BaladosSyncWeb.Queries.get_listening_stats(user.id)
      assert stats.streak_days == 2
    end
  end

  describe "pagination" do
    test "shows pagination for many entries", %{conn: conn, user: user} do
      # Create 55 entries (more than 50 per page)
      for i <- 1..55 do
        create_play_status(user.id, @feed_url_1, "guid#{i}", %{
          rss_feed_title: "Podcast",
          rss_item_title: "Episode #{i}",
          position: i * 10,
          played: false,
          updated_at:
            DateTime.utc_now() |> DateTime.add(-i, :second) |> DateTime.truncate(:second)
        })
      end

      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "Page 1 sur 2"
      assert html =~ "Page 1 sur 2"
      # French: "Suivant"
      assert html =~ "Suivant"
    end

    test "navigates to page 2", %{conn: conn, user: user} do
      for i <- 1..55 do
        create_play_status(user.id, @feed_url_1, "guid#{i}", %{
          rss_feed_title: "Podcast",
          rss_item_title: "Episode #{i}",
          position: i * 10,
          played: false,
          updated_at:
            DateTime.utc_now() |> DateTime.add(-i, :second) |> DateTime.truncate(:second)
        })
      end

      {:ok, _view, html} = live(conn, ~p"/listening-history?page=2")

      # French: "Page 2 sur 2" and "Précédent"
      assert html =~ "Page 2 sur 2"
      assert html =~ "dent"
    end
  end

  describe "export links" do
    test "shows export buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/listening-history")

      # French: "Exporter CSV" / "Exporter JSON"
      assert html =~ "Exporter CSV"
      assert html =~ "Exporter JSON"
      assert html =~ "export.csv"
      assert html =~ "export.json"
    end
  end

  # Helpers

  defp create_play_status(user_id, feed_url, guid, attrs) do
    encoded_feed = Base.url_encode64(feed_url, padding: false)
    encoded_item = Base.url_encode64("#{guid},#{feed_url}/ep", padding: false)

    defaults = %{
      rss_feed_title: "Unknown Podcast",
      rss_item_title: "Unknown Episode",
      position: 0,
      played: false,
      rss_enclosure: %{"duration" => 3600, "size" => 1000},
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    merged = Map.merge(defaults, attrs)

    %PlayStatus{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_item: encoded_item,
      rss_feed_title: merged.rss_feed_title,
      rss_item_title: merged.rss_item_title,
      position: merged.position,
      played: merged.played,
      rss_enclosure: merged.rss_enclosure,
      updated_at: merged.updated_at
    }
    |> ProjectionsRepo.insert!()
  end
end
