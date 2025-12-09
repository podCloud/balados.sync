defmodule BaladosSyncWeb.WebPrivacyControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserPrivacy

  import Ecto.Query

  describe "check_privacy" do
    test "returns has_privacy: false for unauthenticated user", %{conn: conn} do
      encoded_feed = "dGVzdC1mZWVk"

      conn = get(conn, ~p"/privacy/check/#{encoded_feed}")

      assert json_response(conn, 200) == %{
               "has_privacy" => false,
               "privacy" => nil
             }
    end

    test "returns has_privacy: false when privacy not set", %{conn: conn} do
      # Create a user
      user = create_test_user(conn)
      conn = assign(conn, :current_user, user)

      encoded_feed = "dGVzdC1mZWVk"

      conn = get(conn, ~p"/privacy/check/#{encoded_feed}")

      assert json_response(conn, 200) == %{
               "has_privacy" => false,
               "privacy" => nil
             }
    end

    test "returns privacy level when set", %{conn: conn} do
      # Create a user
      user = create_test_user(conn)
      conn = assign(conn, :current_user, user)

      encoded_feed = "dGVzdC1mZWVk"

      # Insert privacy setting directly
      ProjectionsRepo.insert!(%UserPrivacy{
        user_id: user.id,
        rss_source_feed: encoded_feed,
        rss_source_item: "",
        privacy: "public"
      })

      conn = get(conn, ~p"/privacy/check/#{encoded_feed}")

      assert json_response(conn, 200) == %{
               "has_privacy" => true,
               "privacy" => "public"
             }
    end
  end

  describe "set_privacy" do
    test "returns 401 when unauthenticated", %{conn: conn} do
      encoded_feed = "dGVzdC1mZWVk"

      conn = post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "public"})

      assert response(conn, 401)
      assert json_response(conn, 401)["error"]
    end

    test "sets privacy level and returns success", %{conn: conn} do
      # Create a user
      user = create_test_user(conn)
      conn = assign(conn, :current_user, user)

      encoded_feed = "dGVzdC1mZWVk"

      conn =
        post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "private"})
        |> put_req_header("x-csrf-token", get_csrf_token_from_conn(conn))

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["privacy"] == "private"
    end

    test "stores privacy setting in database", %{conn: conn} do
      # Create a user
      user = create_test_user(conn)
      conn = assign(conn, :current_user, user)

      encoded_feed = "dGVzdC1mZWVk"

      _conn =
        post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "anonymous"})
        |> put_req_header("x-csrf-token", get_csrf_token_from_conn(conn))

      # Verify it was stored
      privacy =
        ProjectionsRepo.one(
          from(p in UserPrivacy,
            where: p.user_id == ^user.id and p.rss_source_feed == ^encoded_feed
          )
        )

      assert privacy != nil
      assert privacy.privacy == "anonymous"
    end

    test "validates privacy level with default to public", %{conn: conn} do
      # Create a user
      user = create_test_user(conn)
      conn = assign(conn, :current_user, user)

      encoded_feed = "dGVzdC1mZWVk"

      # Send invalid privacy level
      conn =
        post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "invalid"})
        |> put_req_header("x-csrf-token", get_csrf_token_from_conn(conn))

      response = json_response(conn, 200)
      # Should default to public
      assert response["privacy"] == "public"
    end
  end

  # Helper functions

  defp create_test_user(_conn) do
    # Import and use existing user creation helper if available
    # For now, create a minimal user struct that matches what the controller expects
    %{
      id: "test-user-#{System.unique_integer()}"
    }
  end

  defp get_csrf_token_from_conn(conn) do
    conn.private[:plug_session]["_csrf_token"]
  end
end
