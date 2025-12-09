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

    # Response should be a list
    assert is_list(response_data)

    # Limit should be respected (max 5 in this case)
    assert length(response_data) <= 5
  end

  test "GET /api/v1/public/trending/episodes returns episodes with correct structure", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/public/trending/episodes?limit=1")

    response_data = json_response(conn, 200)

    # If episodes are returned, verify they have the expected structure
    if Enum.any?(response_data) do
      episode = List.first(response_data)

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
    assert length(response_data) <= 100
  end
end
