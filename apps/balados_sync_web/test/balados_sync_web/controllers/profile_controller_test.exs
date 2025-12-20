defmodule BaladosSyncWeb.ProfileControllerTest do
  @moduledoc """
  Integration tests for ProfileController.

  Tests authentication enforcement, profile settings (edit/update),
  and public profile pages.
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.User

  setup do
    # Create a test user with profile fields
    user_id = Ecto.UUID.generate()

    user =
      %User{}
      |> User.registration_changeset(%{
        email: "profile-test-#{System.unique_integer()}@example.com",
        username: "profileuser#{System.unique_integer([:positive])}",
        password: "TestPassword123!",
        password_confirmation: "TestPassword123!"
      })
      |> Ecto.Changeset.put_change(:id, user_id)
      |> SystemRepo.insert!()

    {:ok, user: user}
  end

  describe "authentication enforcement" do
    test "GET /settings/profile redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/settings/profile")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You must log in to access this page."
    end

    test "PUT /settings/profile redirects to login when not authenticated", %{conn: conn} do
      conn = put(conn, ~p"/settings/profile", %{"user" => %{"public_name" => "Test"}})

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /settings/profile (edit)" do
    test "renders profile settings form when authenticated", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/settings/profile")

      assert html_response(conn, 200) =~ "Profile Settings"
      assert html_response(conn, 200) =~ "Display Name"
      assert html_response(conn, 200) =~ "Bio"
      assert html_response(conn, 200) =~ "Enable public profile"
    end

    test "shows current profile values in form", %{conn: conn, user: user} do
      # Update user with profile data
      user
      |> User.profile_changeset(%{public_name: "My Display Name", bio: "Test bio"})
      |> SystemRepo.update!()

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/settings/profile")

      assert html_response(conn, 200) =~ "My Display Name"
      assert html_response(conn, 200) =~ "Test bio"
    end
  end

  describe "PUT /settings/profile (update)" do
    test "updates profile and redirects on success", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn =
        put(conn, ~p"/settings/profile", %{
          "user" => %{
            "public_name" => "New Display Name",
            "bio" => "New bio text",
            "public_profile_enabled" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/settings/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Profile updated successfully."

      # Verify the update persisted
      updated_user = SystemRepo.get!(User, user.id)
      assert updated_user.public_name == "New Display Name"
      assert updated_user.bio == "New bio text"
      assert updated_user.public_profile_enabled == true
    end

    test "clears optional fields when empty strings submitted", %{conn: conn, user: user} do
      # First set some values
      user
      |> User.profile_changeset(%{public_name: "Initial Name", bio: "Initial bio"})
      |> SystemRepo.update!()

      conn = log_in_user(conn, user)

      conn =
        put(conn, ~p"/settings/profile", %{
          "user" => %{
            "public_name" => "",
            "bio" => ""
          }
        })

      assert redirected_to(conn) == ~p"/settings/profile"

      # Verify the fields are cleared
      updated_user = SystemRepo.get!(User, user.id)
      assert updated_user.public_name == "" or updated_user.public_name == nil
      assert updated_user.bio == "" or updated_user.bio == nil
    end

    test "shows error when public_name is too long", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      long_name = String.duplicate("a", 101)

      conn =
        put(conn, ~p"/settings/profile", %{
          "user" => %{"public_name" => long_name}
        })

      assert html_response(conn, 200) =~ "Profile Settings"
      assert html_response(conn, 200) =~ "should be at most 100 character(s)"
    end

    test "shows error when bio is too long", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      long_bio = String.duplicate("a", 501)

      conn =
        put(conn, ~p"/settings/profile", %{
          "user" => %{"bio" => long_bio}
        })

      assert html_response(conn, 200) =~ "Profile Settings"
      assert html_response(conn, 200) =~ "should be at most 500 character(s)"
    end
  end

  describe "GET /u/:username (public profile)" do
    test "shows public profile when user exists and profile is enabled", %{conn: conn, user: user} do
      # Enable the public profile
      user
      |> User.profile_changeset(%{
        public_profile_enabled: true,
        public_name: "Public Name",
        bio: "A visible bio"
      })
      |> SystemRepo.update!()

      conn = get(conn, ~p"/u/#{user.username}")

      assert html_response(conn, 200) =~ "Public Name"
      assert html_response(conn, 200) =~ "A visible bio"
      assert html_response(conn, 200) =~ "@#{user.username}"
    end

    test "shows username when public_name is not set", %{conn: conn, user: user} do
      # Enable the public profile without a display name
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      conn = get(conn, ~p"/u/#{user.username}")

      # Should show the username as display name
      assert html_response(conn, 200) =~ user.username
    end

    test "returns 404 when user does not exist", %{conn: conn} do
      conn = get(conn, ~p"/u/nonexistent_user_12345")

      assert html_response(conn, 404)
    end

    test "returns 404 when public profile is disabled", %{conn: conn, user: user} do
      # Ensure profile is disabled (default)
      user
      |> User.profile_changeset(%{public_profile_enabled: false})
      |> SystemRepo.update!()

      conn = get(conn, ~p"/u/#{user.username}")

      assert html_response(conn, 404)
    end

    test "shows empty state when user has no public activity", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      conn = get(conn, ~p"/u/#{user.username}")

      assert html_response(conn, 200) =~ "No public activity yet"
    end
  end

  # Helper functions

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{"user_token" => user.id})
  end
end
