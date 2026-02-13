defmodule BaladosSyncWeb.PublicControllerTest do
  use BaladosSyncWeb.ConnCase

  test "GET /api/v1/public/trending/episodes returns 200 and valid JSON", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/public/trending/episodes")

    # Should return 200 OK
    assert json_response(conn, 200)
  end

  test "GET /api/v1/public/trending/episodes with feed parameter", %{conn: conn} do
    # The endpoint accepts feed parameter to filter by specific podcast
    conn = get(conn, ~p"/api/v1/public/trending/episodes?feed=test-feed")

    assert json_response(conn, 200)
  end

  test "GET /api/v1/public/trending/episodes respects limit parameter", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/public/trending/episodes?limit=5")

    response_data = json_response(conn, 200)

    # Response wraps episodes in a map
    assert is_list(response_data["episodes"])

    # Limit should be respected (max 5 in this case)
    assert length(response_data["episodes"]) <= 5
  end

  test "GET /api/v1/public/trending/episodes returns episodes with correct structure", %{
    conn: conn
  } do
    conn = get(conn, ~p"/api/v1/public/trending/episodes?limit=1")

    response_data = json_response(conn, 200)
    episodes = response_data["episodes"]

    # If episodes are returned, verify they have the expected structure
    if Enum.any?(episodes) do
      episode = List.first(episodes)

      # Verify required fields from EpisodePopularity schema
      assert Map.has_key?(episode, "rss_source_item")
      assert Map.has_key?(episode, "episode_title")
      assert Map.has_key?(episode, "score")
      assert Map.has_key?(episode, "plays")
      assert Map.has_key?(episode, "likes")
    end
  end

  test "GET /api/v1/public/trending/episodes enforces maximum limit", %{conn: conn} do
    # Request a very high limit
    conn = get(conn, ~p"/api/v1/public/trending/episodes?limit=1000")

    response_data = json_response(conn, 200)

    # The controller should cap at 100
    assert length(response_data["episodes"]) <= 100
  end

  describe "pagination validation" do
    test "trending_podcasts handles non-integer limit", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/public/trending/podcasts?limit=abc")
      assert json_response(conn, 200)
    end

    test "trending_episodes handles non-integer limit", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/public/trending/episodes?limit=abc")
      assert json_response(conn, 200)
    end

    test "trending_podcasts handles negative limit", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/public/trending/podcasts?limit=-10")
      assert json_response(conn, 200)
    end

    test "trending_episodes handles negative limit", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/public/trending/episodes?limit=-10")
      assert json_response(conn, 200)
    end

    test "timeline handles non-integer limit and offset", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/public/timeline?limit=abc&offset=xyz")
      assert json_response(conn, 200)
    end
  end
end
