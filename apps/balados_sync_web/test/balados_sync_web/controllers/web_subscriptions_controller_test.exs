defmodule BaladosSyncWeb.WebSubscriptionsControllerTest do
  @moduledoc """
  Integration tests for WebSubscriptionsController OPML import/export functionality.

  Tests authentication enforcement, file validation, import success/error flows,
  and export in both standard and extended formats.
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{User, Subscription}

  setup do
    # Create a test user
    user_id = Ecto.UUID.generate()

    user =
      %User{}
      |> User.registration_changeset(%{
        email: "opml-test-#{System.unique_integer()}@example.com",
        username: "opmluser#{System.unique_integer()}",
        password: "TestPassword123!",
        password_confirmation: "TestPassword123!"
      })
      |> Ecto.Changeset.put_change(:id, user_id)
      |> SystemRepo.insert!()

    {:ok, user: user}
  end

  describe "authentication enforcement" do
    test "GET /subscriptions/export.opml redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/subscriptions/export.opml")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "GET /subscriptions/import redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/subscriptions/import")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "POST /subscriptions/import redirects to login when not authenticated", %{conn: conn} do
      conn = post(conn, ~p"/subscriptions/import", %{})

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /subscriptions/import (form)" do
    test "renders import form when authenticated", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/subscriptions/import")

      assert html_response(conn, 200) =~ "Import"
    end
  end

  describe "GET /subscriptions/export.opml" do
    test "exports OPML in extended format by default", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create a subscription for the user
      insert_subscription(user.id, "https://example.com/feed.xml")

      conn = get(conn, ~p"/subscriptions/export.opml")

      assert response_content_type(conn, :xml)
      body = response(conn, 200)
      assert body =~ "<opml"
      assert body =~ "balados:"
      # Check filename in content-disposition header
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "balados-sync-export.opml"
    end

    test "exports OPML in standard format when format=standard", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      insert_subscription(user.id, "https://example.com/feed.xml")

      conn = get(conn, ~p"/subscriptions/export.opml?format=standard")

      assert response_content_type(conn, :xml)
      body = response(conn, 200)
      assert body =~ "<opml"
      # Standard format should not have balados namespace attributes
      refute body =~ "balados:playStatuses"
      # Check filename in content-disposition header
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "balados-subscriptions.opml"
    end

    test "exports empty OPML when no subscriptions", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/subscriptions/export.opml")

      assert response_content_type(conn, :xml)
      body = response(conn, 200)
      assert body =~ "<opml"
      assert body =~ "<body>"
    end
  end

  describe "POST /subscriptions/import" do
    test "imports valid OPML file successfully", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      opml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
        <head><title>Test Subscriptions</title></head>
        <body>
          <outline text="Test Podcast" type="rss" xmlUrl="https://example.com/test.xml"/>
        </body>
      </opml>
      """

      upload = create_temp_upload(opml_content, "test.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert redirected_to(conn) == ~p"/subscriptions"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Import successful"
    end

    test "imports extended OPML with play statuses", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      opml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.app/opml">
        <head><title>Extended Export</title></head>
        <body>
          <outline text="Test Podcast" type="rss" xmlUrl="https://example.com/test.xml">
            <outline balados:type="playStatuses">
              <outline balados:type="playStatus"
                       balados:guid="ep1"
                       balados:position="120"
                       balados:played="false"/>
            </outline>
          </outline>
        </body>
      </opml>
      """

      upload = create_temp_upload(opml_content, "extended.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert redirected_to(conn) == ~p"/subscriptions"
      flash = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash =~ "Import successful" or flash =~ "subscription"
    end

    test "shows error for invalid XML", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      invalid_content = "not valid xml at all <>"

      upload = create_temp_upload(invalid_content, "invalid.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert html_response(conn, 200) =~ "Error parsing OPML file"
    end

    test "handles non-OPML XML gracefully", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      non_opml_xml = """
      <?xml version="1.0"?>
      <rss version="2.0"><channel><title>Not OPML</title></channel></rss>
      """

      upload = create_temp_upload(non_opml_xml, "rss.xml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      # Parser may fail or treat as empty OPML - both are acceptable
      # Either redirects to /subscriptions or shows error form
      case conn.status do
        302 ->
          assert redirected_to(conn) == ~p"/subscriptions"

        200 ->
          body = html_response(conn, 200)
          assert body =~ "Invalid" or body =~ "error" or body =~ "Error" or body =~ "Import"
      end
    end

    test "shows error when no file selected", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/subscriptions/import", %{})

      assert html_response(conn, 200) =~ "No file selected"
    end

    test "rejects files larger than 10MB", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Create a file larger than 10MB
      large_content = String.duplicate("x", 11 * 1024 * 1024)
      upload = create_temp_upload(large_content, "large.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert html_response(conn, 200) =~ "File is too large"
    end

    test "imports playlists from extended OPML", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      opml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.app/opml">
        <head><title>Extended Export</title></head>
        <body>
          <outline text="Playlists" balados:type="playlists">
            <outline text="My Favorites" balados:type="playlist" balados:name="My Favorites" balados:description="Best episodes"/>
          </outline>
        </body>
      </opml>
      """

      upload = create_temp_upload(opml_content, "playlists.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert redirected_to(conn) == ~p"/subscriptions"
      flash = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash =~ "Import successful" or flash =~ "playlist"
    end

    test "imports collections from extended OPML", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      opml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0" xmlns:balados="https://balados.app/opml">
        <head><title>Extended Export</title></head>
        <body>
          <outline text="Collections" balados:type="collections">
            <outline text="News" balados:type="collection" balados:title="News" balados:color="#FF0000"/>
          </outline>
        </body>
      </opml>
      """

      upload = create_temp_upload(opml_content, "collections.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert redirected_to(conn) == ~p"/subscriptions"
      flash = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash =~ "Import successful" or flash =~ "collection"
    end

    test "shows 'no new data' message when importing empty OPML", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      opml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
        <head><title>Empty</title></head>
        <body></body>
      </opml>
      """

      upload = create_temp_upload(opml_content, "empty.opml")

      conn = post(conn, ~p"/subscriptions/import", %{"opml" => upload})

      assert redirected_to(conn) == ~p"/subscriptions"
      flash = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash =~ "No new data"
    end
  end

  # Helper functions

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{"user_token" => user.id})
  end

  defp insert_subscription(user_id, feed_url) do
    encoded_feed = Base.url_encode64(feed_url, padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Subscription{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_id: "test-#{System.unique_integer()}",
      subscribed_at: now,
      inserted_at: now,
      updated_at: now
    }
    |> ProjectionsRepo.insert!()
  end

  defp create_temp_upload(content, filename) do
    # Create a temp file with the content
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer()}_#{filename}")
    File.write!(path, content)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: "application/xml"
    }
  end
end
