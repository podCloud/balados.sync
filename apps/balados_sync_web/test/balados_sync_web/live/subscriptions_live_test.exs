defmodule BaladosSyncWeb.SubscriptionsLiveTest do
  @moduledoc """
  Tests for async metadata loading in SubscriptionsLive.

  These tests verify:
  - Initial mount shows subscriptions without metadata (fast path)
  - Metadata loads asynchronously after `connected?`
  - Timeout handling for metadata loading
  - Collection filtering with partial metadata
  - Empty subscriptions list behavior
  """

  use BaladosSyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.{Collection, CollectionSubscription, Subscription, User}

  @feed_url_1 "https://example.com/podcast1.xml"
  @feed_url_2 "https://example.com/podcast2.xml"
  @feed_url_3 "https://example.com/podcast3.xml"

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

    # Setup conn with authenticated session
    conn =
      build_conn()
      |> init_test_session(%{"user_token" => user.id})

    {:ok, conn: conn, user: user}
  end

  describe "initial mount (fast path)" do
    test "renders subscriptions without metadata initially", %{conn: conn, user: user} do
      # Create subscriptions directly in DB
      create_subscription(user.id, @feed_url_1, "Podcast One")
      create_subscription(user.id, @feed_url_2, "Podcast Two")

      # Pre-populate cache with metadata (will be loaded async)
      cache_metadata(@feed_url_1, %{title: "Podcast One Metadata", description: "Description 1"})
      cache_metadata(@feed_url_2, %{title: "Podcast Two Metadata", description: "Description 2"})

      # Static render should show fallback title, not metadata title
      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      # Should show fallback RSS title or "Loading..."
      assert html =~ "Podcast One" or html =~ "Loading..."
      assert html =~ "2 subscriptions"
    end

    test "shows loading indicator during metadata fetch", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, "Podcast One")
      cache_metadata(@feed_url_1, %{title: "Podcast One Metadata"})

      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      # The loading_metadata assign starts as true
      # Check for loading indicator text
      assert html =~ "Loading details..."
    end

    test "renders empty state when no subscriptions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      assert html =~ "No subscriptions yet"
      assert html =~ "Add your first podcast"
    end
  end

  describe "async metadata loading" do
    test "loads metadata asynchronously after connected", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, nil)

      # Cache metadata that will be loaded
      cache_metadata(@feed_url_1, %{
        title: "Async Loaded Title",
        description: "Async Description",
        cover: %{src: "https://example.com/cover.jpg"}
      })

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Wait for async metadata to load
      # The handle_info(:load_metadata, ...) should be processed
      :timer.sleep(100)

      # Re-render to get updated state
      html = render(view)

      # Should now show metadata title
      assert html =~ "Async Loaded Title"
      # Loading indicator should be gone
      refute html =~ "Loading details..."
    end

    test "handles multiple subscriptions metadata loading", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, nil)
      create_subscription(user.id, @feed_url_2, nil)
      create_subscription(user.id, @feed_url_3, nil)

      cache_metadata(@feed_url_1, %{title: "Podcast Alpha"})
      cache_metadata(@feed_url_2, %{title: "Podcast Beta"})
      cache_metadata(@feed_url_3, %{title: "Podcast Gamma"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      :timer.sleep(200)
      html = render(view)

      assert html =~ "Podcast Alpha"
      assert html =~ "Podcast Beta"
      assert html =~ "Podcast Gamma"
      assert html =~ "3 subscriptions"
    end
  end

  describe "metadata fallback handling" do
    test "shows RSS feed title when metadata fetch fails", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, "Fallback Title")

      # Cache an :error value to simulate failed fetch
      # This mimics what happens when Task.async_stream timeout occurs
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_1}, :fetch_failed)

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      :timer.sleep(200)
      html = render(view)

      # Should fall back to RSS title when metadata fetch fails
      # Since fetch_metadata_safe returns nil for invalid metadata,
      # the template uses rss_feed_title as fallback
      assert html =~ "Fallback Title"
    end

    test "shows Loading... when no rss_feed_title and metadata is nil", %{conn: conn, user: user} do
      # Create subscription without RSS title
      create_subscription(user.id, @feed_url_1, nil)

      # Don't cache any metadata - will attempt HTTP fetch
      # Pre-populate with fetch error to prevent actual HTTP call
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_1}, :fetch_failed)

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      :timer.sleep(200)
      html = render(view)

      # Without metadata title or rss_feed_title, should show Loading...
      assert html =~ "Loading..."
    end

    test "preserves subscription order on partial metadata failure", %{conn: conn, user: user} do
      # Create subscriptions in specific order
      create_subscription(user.id, @feed_url_1, "First")
      create_subscription(user.id, @feed_url_2, "Second")
      create_subscription(user.id, @feed_url_3, "Third")

      # Only cache some metadata - others will use fallback titles
      cache_metadata(@feed_url_1, %{title: "First Loaded"})
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_2}, :fetch_failed)
      cache_metadata(@feed_url_3, %{title: "Third Loaded"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      :timer.sleep(200)
      html = render(view)

      # Should still show 3 subscriptions
      assert html =~ "3 subscriptions"
      # First and third have loaded titles, second uses fallback
      assert html =~ "First Loaded"
      assert html =~ "Second"
      assert html =~ "Third Loaded"
    end
  end

  describe "collection filtering with metadata" do
    test "filters subscriptions by collection after metadata loads", %{conn: conn, user: user} do
      sub1 = create_subscription(user.id, @feed_url_1, "Podcast One")
      sub2 = create_subscription(user.id, @feed_url_2, "Podcast Two")
      _sub3 = create_subscription(user.id, @feed_url_3, "Podcast Three")

      # Create a collection with only first two subscriptions
      collection = create_collection(user.id, "My Collection", "#ff0000")
      add_to_collection(collection.id, sub1.rss_source_feed)
      add_to_collection(collection.id, sub2.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "Loaded One"})
      cache_metadata(@feed_url_2, %{title: "Loaded Two"})
      cache_metadata(@feed_url_3, %{title: "Loaded Three"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      :timer.sleep(200)
      html = render(view)

      # Should show filtered count
      assert html =~ "2 subscriptions"
      # Should show collection title
      assert html =~ "My Collection"
    end

    test "re-applies filter after metadata loads", %{conn: conn, user: user} do
      sub1 = create_subscription(user.id, @feed_url_1, nil)
      create_subscription(user.id, @feed_url_2, nil)

      collection = create_collection(user.id, "Filtered Collection", "#00ff00")
      add_to_collection(collection.id, sub1.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "In Collection"})
      cache_metadata(@feed_url_2, %{title: "Not In Collection"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      :timer.sleep(200)
      html = render(view)

      # Should only show subscription in collection
      assert html =~ "In Collection"
      refute html =~ "Not In Collection"
      assert html =~ "1 subscription"
    end

    test "handles empty collection with metadata", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, nil)
      cache_metadata(@feed_url_1, %{title: "Not in any collection"})

      collection = create_collection(user.id, "Empty Collection", "#0000ff")

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      :timer.sleep(100)
      html = render(view)

      assert html =~ "No subscriptions in this collection"
    end
  end

  describe "race condition: filtering before metadata loads" do
    test "filter change during metadata loading preserves correct state", %{
      conn: conn,
      user: user
    } do
      sub1 = create_subscription(user.id, @feed_url_1, "Sub One")
      _sub2 = create_subscription(user.id, @feed_url_2, "Sub Two")

      collection = create_collection(user.id, "Test Collection", "#123456")
      add_to_collection(collection.id, sub1.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "Metadata One"})
      cache_metadata(@feed_url_2, %{title: "Metadata Two"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Immediately filter before metadata fully loads
      view |> element("button", "Test Collection") |> render_click()

      # Wait for everything to settle
      :timer.sleep(200)
      html = render(view)

      # Should show filtered view with metadata
      assert html =~ "1 subscription"
      assert html =~ "Metadata One"
      refute html =~ "Metadata Two"
    end

    test "switching filters during async load maintains consistency", %{conn: conn, user: user} do
      sub1 = create_subscription(user.id, @feed_url_1, "Sub A")
      sub2 = create_subscription(user.id, @feed_url_2, "Sub B")

      col1 = create_collection(user.id, "Collection A", "#aaaaaa")
      col2 = create_collection(user.id, "Collection B", "#bbbbbb")

      add_to_collection(col1.id, sub1.rss_source_feed)
      add_to_collection(col2.id, sub2.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "Meta A"})
      cache_metadata(@feed_url_2, %{title: "Meta B"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Switch to collection A
      view |> element("button", "Collection A") |> render_click()

      # Then to collection B
      view |> element("button", "Collection B") |> render_click()

      :timer.sleep(200)
      html = render(view)

      # Should be in Collection B with correct subscription
      assert html =~ "Collection B"
      assert html =~ "Meta B"
      refute html =~ "Meta A"
    end
  end

  describe "guard against race conditions" do
    test "loading_metadata guard prevents duplicate processing", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, "Test")
      cache_metadata(@feed_url_1, %{title: "Test Metadata"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Wait for initial load
      :timer.sleep(100)

      # Manually send load_metadata message (simulating race)
      # This should be ignored due to loading_metadata being false
      send(view.pid, :load_metadata)

      :timer.sleep(50)
      html = render(view)

      # Should still work correctly
      assert html =~ "Test Metadata"
      refute html =~ "Loading details..."
    end
  end

  # Helper functions

  defp create_subscription(user_id, feed_url, rss_title) do
    encoded_feed = Base.url_encode64(feed_url, padding: false)

    %Subscription{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_feed_title: rss_title,
      subscribed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
    |> ProjectionsRepo.insert!()
  end

  defp create_collection(user_id, title, color) do
    %Collection{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      title: title,
      color: color,
      is_default: false
    }
    |> ProjectionsRepo.insert!()
  end

  defp add_to_collection(collection_id, encoded_feed) do
    %CollectionSubscription{
      id: Ecto.UUID.generate(),
      collection_id: collection_id,
      rss_source_feed: encoded_feed
    }
    |> ProjectionsRepo.insert!()
  end

  defp cache_metadata(feed_url, metadata) do
    # Pre-populate the RssCache with metadata
    # This prevents actual HTTP requests during tests
    # Ensure all expected keys exist (with defaults) to avoid KeyError in templates
    complete_metadata =
      Map.merge(
        %{title: nil, description: nil, cover: nil},
        metadata
      )

    cache_key = {:metadata, feed_url}
    Cachex.put(:rss_feed_cache, cache_key, complete_metadata)
  end
end
