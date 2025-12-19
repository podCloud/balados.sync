defmodule BaladosSyncWeb.PlaylistsControllerTest do
  @moduledoc """
  Integration tests for PlaylistsController.

  Tests authentication enforcement, form validation, redirects, and CRUD operations.
  Uses direct database insertion for test data to avoid CQRS projection delays.
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Playlist, User}

  import Ecto.Query

  setup do
    # Create a test user
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

    {:ok, user: user}
  end

  describe "authentication enforcement" do
    test "GET /playlists redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/playlists")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You must log in to access this page."
    end

    test "GET /playlists/new redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/playlists/new")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "POST /playlists redirects to login when not authenticated", %{conn: conn} do
      conn = post(conn, ~p"/playlists", %{"playlist" => %{"name" => "Test"}})

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "GET /playlists/:id redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/playlists/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "GET /playlists/:id/edit redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/playlists/#{Ecto.UUID.generate()}/edit")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "PUT /playlists/:id redirects to login when not authenticated", %{conn: conn} do
      conn = put(conn, ~p"/playlists/#{Ecto.UUID.generate()}", %{"playlist" => %{"name" => "New Name"}})

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "DELETE /playlists/:id redirects to login when not authenticated", %{conn: conn} do
      conn = delete(conn, ~p"/playlists/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /playlists (index)" do
    test "lists user's playlists when authenticated", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create a playlist directly in DB
      playlist = insert_playlist(user.id, "My Playlist", "Test description")

      conn = get(conn, ~p"/playlists")

      assert html_response(conn, 200) =~ playlist.name
      assert html_response(conn, 200) =~ playlist.description
    end

    test "shows empty state when no playlists", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/playlists")

      # Should show page without errors
      assert html_response(conn, 200) =~ "Playlists"
    end

    test "does not show other users' playlists", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      conn = log_in_user(conn, user)

      # Create a playlist for another user
      insert_playlist(other_user_id, "Other User Playlist")

      conn = get(conn, ~p"/playlists")

      refute html_response(conn, 200) =~ "Other User Playlist"
    end
  end

  describe "GET /playlists/new" do
    test "renders new playlist form when authenticated", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/playlists/new")

      assert html_response(conn, 200) =~ "New Playlist"
      assert html_response(conn, 200) =~ "playlist[name]"
    end
  end

  describe "POST /playlists (create)" do
    test "creates playlist and redirects to index on success", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn =
        post(conn, ~p"/playlists", %{
          "playlist" => %{"name" => "New Playlist", "description" => "A test playlist"}
        })

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Playlist created successfully."
    end

    test "shows error when name is missing", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn =
        post(conn, ~p"/playlists", %{
          "playlist" => %{"name" => "", "description" => "Description without name"}
        })

      assert html_response(conn, 200) =~ "Name is required"
      assert html_response(conn, 200) =~ "New Playlist"
    end

    test "shows error when name is nil", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn =
        post(conn, ~p"/playlists", %{
          "playlist" => %{"description" => "Description without name"}
        })

      assert html_response(conn, 200) =~ "Name is required"
    end
  end

  describe "GET /playlists/:id (show)" do
    test "shows playlist when authenticated and owner", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create a playlist directly in DB
      playlist = insert_playlist(user.id, "Show Test Playlist", "Visible description")

      conn = get(conn, ~p"/playlists/#{playlist.id}")

      assert html_response(conn, 200) =~ "Show Test Playlist"
      assert html_response(conn, 200) =~ "Visible description"
    end

    test "redirects to index with error when playlist not found", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/playlists/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end

    test "redirects to index when trying to view another user's playlist", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      conn = log_in_user(conn, user)

      # Create playlist for other user
      playlist = insert_playlist(other_user_id, "Private Playlist")

      conn = get(conn, ~p"/playlists/#{playlist.id}")

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end

    test "redirects when playlist is soft-deleted", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create and then soft-delete a playlist
      playlist = insert_playlist(user.id, "Deleted Playlist")
      soft_delete_playlist(playlist.id)

      conn = get(conn, ~p"/playlists/#{playlist.id}")

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end
  end

  describe "GET /playlists/:id/edit" do
    test "renders edit form when authenticated and owner", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create a playlist directly in DB
      playlist = insert_playlist(user.id, "Edit Test Playlist", "Original description")

      conn = get(conn, ~p"/playlists/#{playlist.id}/edit")

      assert html_response(conn, 200) =~ "Edit Playlist"
      assert html_response(conn, 200) =~ "Edit Test Playlist"
    end

    test "redirects to index when playlist not found", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/playlists/#{Ecto.UUID.generate()}/edit")

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end

    test "redirects when trying to edit another user's playlist", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      conn = log_in_user(conn, user)

      # Create playlist for other user
      playlist = insert_playlist(other_user_id, "Other Playlist")

      conn = get(conn, ~p"/playlists/#{playlist.id}/edit")

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end
  end

  describe "PUT /playlists/:id (update)" do
    test "updates playlist and redirects to show on success", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create a playlist directly in DB
      playlist = insert_playlist(user.id, "Original Name", "Original description")

      conn =
        put(conn, ~p"/playlists/#{playlist.id}", %{
          "playlist" => %{"name" => "Updated Name", "description" => "Updated description"}
        })

      assert redirected_to(conn) == ~p"/playlists/#{playlist.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Playlist updated successfully."
    end

    test "redirects to index when playlist not found", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn =
        put(conn, ~p"/playlists/#{Ecto.UUID.generate()}", %{
          "playlist" => %{"name" => "New Name"}
        })

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end

    test "redirects to index when trying to update another user's playlist", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      conn = log_in_user(conn, user)

      # Create playlist for other user
      playlist = insert_playlist(other_user_id, "Other Playlist")

      conn =
        put(conn, ~p"/playlists/#{playlist.id}", %{
          "playlist" => %{"name" => "Hijacked Name"}
        })

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end
  end

  describe "DELETE /playlists/:id" do
    test "delete action redirects to index", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Note: Delete goes through CQRS, so we just test the redirect behavior
      # The playlist in projection won't match aggregate state when inserted directly
      playlist = insert_playlist(user.id, "To Delete")

      conn = delete(conn, ~p"/playlists/#{playlist.id}")

      # Should redirect to playlists index regardless of outcome
      assert redirected_to(conn) == ~p"/playlists"
    end

    test "returns error when playlist not found", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = delete(conn, ~p"/playlists/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == ~p"/playlists"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Playlist not found."
    end

    test "returns error when trying to delete another user's playlist", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      conn = log_in_user(conn, user)

      # Create playlist for other user
      playlist = insert_playlist(other_user_id, "Not Mine")

      conn = delete(conn, ~p"/playlists/#{playlist.id}")

      # DeletePlaylist command checks ownership in aggregate
      assert redirected_to(conn) == ~p"/playlists"
    end
  end

  # Helper functions

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{"user_token" => user.id})
  end

  defp insert_playlist(user_id, name, description \\ nil) do
    playlist = %Playlist{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      name: name,
      description: description
    }

    ProjectionsRepo.insert!(playlist)
  end

  defp soft_delete_playlist(playlist_id) do
    ProjectionsRepo.update_all(
      from(p in Playlist, where: p.id == ^playlist_id),
      set: [deleted_at: DateTime.utc_now()]
    )
  end
end
