defmodule BaladosSyncWeb.WebPrivacyControllerTest do
  use BaladosSyncWeb.ConnCase

  import Ecto.Query
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserPrivacy
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.User

  defp create_and_login_user(conn) do
    user =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "test-#{System.unique_integer([:positive])}@example.com",
        username: "testuser#{System.unique_integer([:positive])}",
        hashed_password: Argon2.hash_pwd_salt("TestPassword1!", t_cost: 1, m_cost: 8)
      })
      |> SystemRepo.insert!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_token: user.id})

    {conn, user}
  end

  describe "check_privacy" do
    test "returns has_privacy: false for unauthenticated user", %{conn: conn} do
      encoded_feed = "dGVzdC1mZWVk"

      conn = get(conn, ~p"/privacy/check/#{encoded_feed}")

      assert json_response(conn, 200)["has_privacy"] == false
    end

    test "returns has_privacy: false when privacy not set", %{conn: conn} do
      {conn, _user} = create_and_login_user(conn)
      encoded_feed = "dGVzdC1mZWVk"

      conn = get(conn, ~p"/privacy/check/#{encoded_feed}")

      assert json_response(conn, 200) == %{
               "has_privacy" => false,
               "privacy" => nil
             }
    end

    test "returns privacy level when set", %{conn: conn} do
      {conn, user} = create_and_login_user(conn)
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
      {conn, _user} = create_and_login_user(conn)
      encoded_feed = "dGVzdC1mZWVk"

      conn = post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "private"})

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["privacy"] == "private"
    end

    test "dispatches privacy command successfully", %{conn: conn} do
      {conn, _user} = create_and_login_user(conn)
      encoded_feed = "dGVzdC1mZWVk"

      conn = post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "anonymous"})

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["privacy"] == "anonymous"
    end

    test "validates privacy level with default to public", %{conn: conn} do
      {conn, _user} = create_and_login_user(conn)
      encoded_feed = "dGVzdC1mZWVk"

      # Send invalid privacy level
      conn = post(conn, ~p"/privacy/set/#{encoded_feed}", %{"privacy" => "invalid"})

      response = json_response(conn, 200)
      # Should default to public
      assert response["privacy"] == "public"
    end
  end
end
