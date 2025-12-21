defmodule BaladosSyncWeb.ProfileControllerTest do
  @moduledoc """
  Integration tests for ProfileController.

  Tests authentication enforcement, profile settings (edit/update),
  public profile pages, and public playlist/collection pages.
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{User, Playlist, Collection}

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

    test "shows public playlists on profile page", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create a public playlist
      insert_playlist(user.id, "My Public Playlist", "A playlist description", true)

      conn = get(conn, ~p"/u/#{user.username}")

      assert html_response(conn, 200) =~ "My Public Playlist"
    end

    test "does not show private playlists on profile page", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create a private playlist
      insert_playlist(user.id, "Secret Playlist", "Private description", false)

      conn = get(conn, ~p"/u/#{user.username}")

      refute html_response(conn, 200) =~ "Secret Playlist"
    end

    test "shows public collections on profile page", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create a public collection
      insert_collection(user.id, "My Public Collection", "A collection description", true)

      conn = get(conn, ~p"/u/#{user.username}")

      assert html_response(conn, 200) =~ "My Public Collection"
    end

    test "does not show private collections on profile page", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create a private collection
      insert_collection(user.id, "Private Collection", "Private description", false)

      conn = get(conn, ~p"/u/#{user.username}")

      refute html_response(conn, 200) =~ "Private Collection"
    end
  end

  describe "GET /u/:username/playlists/:id (show_playlist)" do
    test "shows public playlist with details", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      playlist = insert_playlist(user.id, "Great Episodes", "My favorite podcast episodes", true)

      conn = get(conn, ~p"/u/#{user.username}/playlists/#{playlist.id}")

      assert html_response(conn, 200) =~ "Great Episodes"
      assert html_response(conn, 200) =~ "My favorite podcast episodes"
      assert html_response(conn, 200) =~ "@#{user.username}"
    end

    test "shows empty state when playlist has no items", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      playlist = insert_playlist(user.id, "Empty Playlist", nil, true)

      conn = get(conn, ~p"/u/#{user.username}/playlists/#{playlist.id}")

      assert html_response(conn, 200) =~ "This playlist is empty"
    end

    test "returns 404 for private playlist", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      playlist = insert_playlist(user.id, "Private Playlist", nil, false)

      conn = get(conn, ~p"/u/#{user.username}/playlists/#{playlist.id}")

      assert html_response(conn, 404)
    end

    test "returns 404 when user profile is disabled", %{conn: conn, user: user} do
      # Profile disabled by default
      playlist = insert_playlist(user.id, "Hidden Playlist", nil, true)

      conn = get(conn, ~p"/u/#{user.username}/playlists/#{playlist.id}")

      assert html_response(conn, 404)
    end

    test "returns 404 for non-existent playlist", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      fake_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/u/#{user.username}/playlists/#{fake_id}")

      assert html_response(conn, 404)
    end

    test "returns 404 for deleted playlist", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      playlist = insert_playlist(user.id, "Deleted Playlist", nil, true)
      soft_delete_playlist(playlist.id)

      conn = get(conn, ~p"/u/#{user.username}/playlists/#{playlist.id}")

      assert html_response(conn, 404)
    end

    test "returns 404 when accessing another user's playlist with wrong username", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create another user with public profile
      other_user = create_test_user("otheruser")
      other_user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create a public playlist for the other user
      playlist = insert_playlist(other_user.id, "Other's Playlist", nil, true)

      # Try to access via first user's username - should 404
      conn = get(conn, ~p"/u/#{user.username}/playlists/#{playlist.id}")

      assert html_response(conn, 404)
    end
  end

  describe "GET /u/:username/collections/:id (show_collection)" do
    test "shows public collection with details", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      collection = insert_collection(user.id, "Tech Podcasts", "My favorite tech shows", true, "blue")

      conn = get(conn, ~p"/u/#{user.username}/collections/#{collection.id}")

      assert html_response(conn, 200) =~ "Tech Podcasts"
      assert html_response(conn, 200) =~ "My favorite tech shows"
      assert html_response(conn, 200) =~ "@#{user.username}"
    end

    test "shows empty state when collection has no feeds", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      collection = insert_collection(user.id, "Empty Collection", nil, true)

      conn = get(conn, ~p"/u/#{user.username}/collections/#{collection.id}")

      assert html_response(conn, 200) =~ "This collection is empty"
    end

    test "returns 404 for private collection", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      collection = insert_collection(user.id, "Private Collection", nil, false)

      conn = get(conn, ~p"/u/#{user.username}/collections/#{collection.id}")

      assert html_response(conn, 404)
    end

    test "returns 404 when user profile is disabled", %{conn: conn, user: user} do
      # Profile disabled by default
      collection = insert_collection(user.id, "Hidden Collection", nil, true)

      conn = get(conn, ~p"/u/#{user.username}/collections/#{collection.id}")

      assert html_response(conn, 404)
    end

    test "returns 404 for non-existent collection", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      fake_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/u/#{user.username}/collections/#{fake_id}")

      assert html_response(conn, 404)
    end

    test "returns 404 for deleted collection", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      collection = insert_collection(user.id, "Deleted Collection", nil, true)
      soft_delete_collection(collection.id)

      conn = get(conn, ~p"/u/#{user.username}/collections/#{collection.id}")

      assert html_response(conn, 404)
    end

    test "returns 404 when accessing another user's collection with wrong username", %{conn: conn, user: user} do
      user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create another user with public profile
      other_user = create_test_user("anotheruser")
      other_user
      |> User.profile_changeset(%{public_profile_enabled: true})
      |> SystemRepo.update!()

      # Create a public collection for the other user
      collection = insert_collection(other_user.id, "Other's Collection", nil, true)

      # Try to access via first user's username - should 404
      conn = get(conn, ~p"/u/#{user.username}/collections/#{collection.id}")

      assert html_response(conn, 404)
    end
  end

  # Helper functions

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{"user_token" => user.id})
  end

  defp create_test_user(username_prefix) do
    user_id = Ecto.UUID.generate()

    %User{}
    |> User.registration_changeset(%{
      email: "#{username_prefix}-#{System.unique_integer()}@example.com",
      username: "#{username_prefix}#{System.unique_integer([:positive])}",
      password: "TestPassword123!",
      password_confirmation: "TestPassword123!"
    })
    |> Ecto.Changeset.put_change(:id, user_id)
    |> SystemRepo.insert!()
  end

  defp insert_playlist(user_id, name, description \\ nil, is_public \\ false) do
    %Playlist{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      name: name,
      description: description,
      is_public: is_public
    }
    |> ProjectionsRepo.insert!()
  end

  defp soft_delete_playlist(playlist_id) do
    import Ecto.Query

    ProjectionsRepo.update_all(
      from(p in Playlist, where: p.id == ^playlist_id),
      set: [deleted_at: DateTime.utc_now()]
    )
  end

  defp insert_collection(user_id, title, description \\ nil, is_public \\ false, color \\ nil) do
    %Collection{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      title: title,
      description: description,
      is_public: is_public,
      is_default: false,
      color: color
    }
    |> ProjectionsRepo.insert!()
  end

  defp soft_delete_collection(collection_id) do
    import Ecto.Query

    ProjectionsRepo.update_all(
      from(c in Collection, where: c.id == ^collection_id),
      set: [deleted_at: DateTime.utc_now()]
    )
  end
end
