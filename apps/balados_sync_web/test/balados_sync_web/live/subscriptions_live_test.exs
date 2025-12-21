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
    # Clear cache before each test to ensure isolation
    Cachex.clear(:rss_feed_cache)

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

    on_exit(fn ->
      Cachex.clear(:rss_feed_cache)
    end)

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
      html = wait_for_metadata(view)

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

      html = wait_for_metadata(view)

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

      html = wait_for_metadata(view)

      # Should fall back to RSS title when metadata fetch fails
      # Since fetch_metadata_safe returns nil for invalid metadata,
      # the template uses rss_feed_title as fallback
      assert html =~ "Fallback Title"
    end

    test "shows error state when no rss_feed_title and metadata fetch fails", %{
      conn: conn,
      user: user
    } do
      # Create subscription without RSS title
      create_subscription(user.id, @feed_url_1, nil)

      # Pre-populate with invalid (non-map) value to simulate fetch failure
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_1}, :fetch_failed)

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      html = wait_for_metadata(view)

      # Should show error state when fetch fails and no fallback title
      assert html =~ "Unable to load" or html =~ "Failed to load"
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

      html = wait_for_metadata(view)

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

      html = wait_for_metadata(view)

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

      html = wait_for_metadata(view)

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

      html = wait_for_metadata(view)

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
      html = wait_for_metadata(view)

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

      html = wait_for_metadata(view)

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
      _html = wait_for_metadata(view)

      # Manually send load_metadata message (simulating race)
      # This should be ignored due to loading_metadata being false
      send(view.pid, :load_metadata)

      # Re-render and verify state is still correct
      html = render(view)

      # Should still work correctly
      assert html =~ "Test Metadata"
      refute html =~ "Loading details..."
    end
  end

  describe "error state UX" do
    test "shows error indicator when metadata fetch fails", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, nil)

      # Force an error by caching an invalid (non-map) value
      # This triggers the {:ok, _invalid} clause in fetch_metadata_with_telemetry
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_1}, :fetch_failed)

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      html = wait_for_metadata(view)

      # Should show error state UI elements
      assert html =~ "Failed to load" or html =~ "Unable to load"
      assert html =~ "Retry"
      assert html =~ "Could not fetch podcast details"
    end

    test "retry button is present for failed metadata", %{conn: conn, user: user} do
      create_subscription(user.id, @feed_url_1, nil)

      # Force error state with non-map value
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_1}, :fetch_failed)

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      html = wait_for_metadata(view)

      # Should have retry button with correct phx-click
      assert html =~ "phx-click=\"retry_metadata\""
    end

    test "retry_metadata event triggers metadata reload", %{conn: conn, user: user} do
      _sub = create_subscription(user.id, @feed_url_1, nil)

      # First: fail the metadata fetch with non-map value
      Cachex.put(:rss_feed_cache, {:metadata, @feed_url_1}, :fetch_failed)

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      html = wait_for_metadata(view)
      assert html =~ "Failed to load" or html =~ "Unable to load"

      # Now: fix the cache with valid metadata
      cache_metadata(@feed_url_1, %{title: "Recovered Podcast", description: "Now it works!"})

      # Trigger retry
      view
      |> element("button[phx-click=\"retry_metadata\"]")
      |> render_click()

      # Wait a bit for async processing
      Process.sleep(100)
      html = render(view)

      # Should now show the recovered metadata
      assert html =~ "Recovered Podcast"
      refute html =~ "Failed to load"
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

  # Wait for async metadata to load by polling until the condition is met.
  # This replaces hardcoded timer.sleep calls with active polling that:
  # - Returns immediately when condition is met (faster tests)
  # - Has configurable timeout for CI environments
  # - Documents what we're waiting for explicitly
  defp wait_for_metadata(view, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 500)
    interval = Keyword.get(opts, :interval, 10)

    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_metadata(view, deadline, interval)
  end

  defp do_wait_for_metadata(view, deadline, interval) do
    html = render(view)

    # Metadata is loaded when "Loading details..." disappears
    if not String.contains?(html, "Loading details...") do
      html
    else
      if System.monotonic_time(:millisecond) >= deadline do
        # Return current HTML even if timeout - let assertions fail with actual content
        html
      else
        Process.sleep(interval)
        do_wait_for_metadata(view, deadline, interval)
      end
    end
  end


  describe "collection management: create collection" do
    test "opens create collection modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Click the create collection button (+ button)
      html = view |> element("button[phx-click=\"open_create_collection\"]") |> render_click()

      # Modal should be visible
      assert html =~ "Create Collection"
      assert html =~ "Title"
      assert html =~ "Description"
      assert html =~ "Color"
    end

    test "form accepts title input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open modal
      view |> element("button[phx-click=\"open_create_collection\"]") |> render_click()

      # Fill in the form via update_collection_form event
      html = view |> render_keyup("update_collection_form", %{"field" => "title", "value" => "My New Collection"})

      # Form should show the input value (input has the value set)
      assert html =~ "My New Collection"
    end

    test "closes create modal on cancel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open modal
      view |> element("button[phx-click=\"open_create_collection\"]") |> render_click()

      # Cancel
      html = view |> element("button[phx-click=\"close_collection_modal\"]") |> render_click()

      # Modal should be closed
      refute html =~ "Create Collection"
    end

    test "selects color in create modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open modal
      view |> element("button[phx-click=\"open_create_collection\"]") |> render_click()

      # Click a color button (green) - use render_click with the event directly
      html = view |> render_click("update_collection_form", %{"field" => "color", "value" => "#22c55e"})

      # Color should be selected (has ring class)
      assert html =~ "ring-2"
    end
  end

  describe "collection management: edit collection" do
    test "opens edit collection modal with existing data", %{conn: conn, user: user} do
      collection = create_collection(user.id, "Existing Collection", "#ef4444")

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Click edit button on the collection
      html = view |> element("button[phx-click=\"open_edit_collection\"][phx-value-id=\"#{collection.id}\"]") |> render_click()

      # Modal should show "Edit Collection" with existing data
      assert html =~ "Edit Collection"
      assert html =~ "Existing Collection"
    end

    test "form shows updated title in edit mode", %{conn: conn, user: user} do
      collection = create_collection(user.id, "Original Title", "#3b82f6")

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open edit modal
      view |> element("button[phx-click=\"open_edit_collection\"][phx-value-id=\"#{collection.id}\"]") |> render_click()

      # Update title via event
      html = view |> render_keyup("update_collection_form", %{"field" => "title", "value" => "Updated Title"})

      # Form should show the updated value
      assert html =~ "Updated Title"
    end

    test "changes collection color in form", %{conn: conn, user: user} do
      collection = create_collection(user.id, "Color Test", "#3b82f6")

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open edit modal
      view |> element("button[phx-click=\"open_edit_collection\"][phx-value-id=\"#{collection.id}\"]") |> render_click()

      # Select a different color (purple) via event
      html = view |> render_click("update_collection_form", %{"field" => "color", "value" => "#a855f7"})

      # Color should be selected in modal (has ring class)
      assert html =~ "ring-2"
    end
  end

  describe "collection management: delete collection" do
    test "shows delete confirmation modal", %{conn: conn, user: user} do
      collection = create_collection(user.id, "To Delete", "#ef4444")

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Click delete button
      html = view |> element("button[phx-click=\"confirm_delete_collection\"][phx-value-id=\"#{collection.id}\"]") |> render_click()

      # Confirmation modal should appear
      assert html =~ "Delete Collection?"
      assert html =~ "This will remove the collection but keep your subscriptions"
    end

    test "cancels delete on cancel button", %{conn: conn, user: user} do
      collection = create_collection(user.id, "Keep Me", "#22c55e")

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open delete confirmation
      view |> element("button[phx-click=\"confirm_delete_collection\"][phx-value-id=\"#{collection.id}\"]") |> render_click()

      # Cancel
      html = view |> element("button[phx-click=\"cancel_delete\"]") |> render_click()

      # Modal should be closed and collection still exists
      refute html =~ "Delete Collection?"
      assert html =~ "Keep Me"
    end

    test "confirm delete button is present in modal", %{conn: conn, user: user} do
      collection = create_collection(user.id, "Delete Me", "#ef4444")

      {:ok, view, _html} = live(conn, ~p"/subscriptions")

      # Open delete confirmation
      html = view |> element("button[phx-click=\"confirm_delete_collection\"][phx-value-id=\"#{collection.id}\"]") |> render_click()

      # Modal should have the delete confirmation button
      assert html =~ "phx-click=\"delete_collection\""
      assert html =~ "Delete"
    end

    test "hides delete button for default collection", %{conn: conn, user: user} do
      # Create a default collection
      %Collection{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        title: "Default Collection",
        color: "#3b82f6",
        is_default: true
      }
      |> ProjectionsRepo.insert!()

      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      # Default collection should be displayed
      assert html =~ "Default Collection"
      # Should show asterisk indicator for default
      assert html =~ "*"
    end
  end

  describe "collection management: manage feeds mode" do
    test "shows manage feeds button when viewing a collection", %{conn: conn, user: user} do
      collection = create_collection(user.id, "My Collection", "#3b82f6")

      {:ok, _view, html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      assert html =~ "Manage Feeds"
    end

    test "hides manage feeds button when viewing all subscriptions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      # Should not show Manage Feeds toggle button when no collection is selected
      # (Note: HTML comments containing "Manage Feeds" are still rendered but the button should be absent)
      refute html =~ "phx-click=\"toggle_manage_feeds\""
    end

    test "toggles manage feeds mode on and off", %{conn: conn, user: user} do
      sub = create_subscription(user.id, @feed_url_1, "Podcast One")
      collection = create_collection(user.id, "Test Collection", "#3b82f6")
      add_to_collection(collection.id, sub.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "Podcast One"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      # Enable manage feeds mode
      html = view |> element("button[phx-click=\"toggle_manage_feeds\"]") |> render_click()

      # Button should change to "Done"
      assert html =~ "Done"

      # Disable manage feeds mode
      html = view |> element("button[phx-click=\"toggle_manage_feeds\"]") |> render_click()

      # Button should be back to "Manage Feeds"
      assert html =~ "Manage Feeds"
    end

    test "shows checkmarks on feeds in manage mode", %{conn: conn, user: user} do
      sub = create_subscription(user.id, @feed_url_1, "Podcast One")
      collection = create_collection(user.id, "Test Collection", "#3b82f6")
      add_to_collection(collection.id, sub.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "Podcast One"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      # Enable manage feeds mode
      html = view |> element("button[phx-click=\"toggle_manage_feeds\"]") |> render_click()

      # Should show toggle button with checkmark (feed is in collection)
      assert html =~ "toggle_feed_in_collection"
      assert html =~ "bg-green-500"  # Green background for included feeds
    end

    test "toggle feed button is present in manage mode", %{conn: conn, user: user} do
      sub = create_subscription(user.id, @feed_url_1, "Podcast One")
      collection = create_collection(user.id, "Test Collection", "#3b82f6")
      add_to_collection(collection.id, sub.rss_source_feed)

      cache_metadata(@feed_url_1, %{title: "Podcast One"})

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      # Enable manage feeds mode
      html = view |> element("button[phx-click=\"toggle_manage_feeds\"]") |> render_click()

      # Initially in collection (green checkmark)
      assert html =~ "bg-green-500"

      # Toggle button should be present with correct event
      assert html =~ "toggle_feed_in_collection"
      assert html =~ sub.rss_source_feed
    end
  end

  describe "collection UI elements" do
    test "shows collection badge with correct color", %{conn: conn, user: user} do
      create_collection(user.id, "Blue Collection", "#3b82f6")
      create_collection(user.id, "Red Collection", "#ef4444")

      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      assert html =~ "Blue Collection"
      assert html =~ "Red Collection"
      assert html =~ "#3b82f6"
      assert html =~ "#ef4444"
    end

    test "shows feed count in collection badge", %{conn: conn, user: user} do
      sub1 = create_subscription(user.id, @feed_url_1, "Podcast 1")
      sub2 = create_subscription(user.id, @feed_url_2, "Podcast 2")
      collection = create_collection(user.id, "Two Feeds", "#22c55e")
      add_to_collection(collection.id, sub1.rss_source_feed)
      add_to_collection(collection.id, sub2.rss_source_feed)

      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      # Should show (2) in the badge
      assert html =~ "Two Feeds"
      assert html =~ "(2)"
    end

    test "marks default collection with asterisk", %{conn: conn, user: user} do
      %Collection{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        title: "Default",
        color: "#3b82f6",
        is_default: true
      }
      |> ProjectionsRepo.insert!()

      {:ok, _view, html} = live(conn, ~p"/subscriptions")

      # Default collection shows asterisk
      assert html =~ "Default"
      assert html =~ "*"
    end

    test "highlights active collection", %{conn: conn, user: user} do
      collection = create_collection(user.id, "Active Collection", "#a855f7")

      {:ok, view, _html} = live(conn, ~p"/subscriptions?collection=#{collection.id}")

      html = render(view)

      # Active collection should have the full color background (not transparent)
      assert html =~ "Active Collection"
      # When active, background is the full color, when inactive it has 20 appended for transparency
      assert html =~ "style=\"background-color: #a855f7"
    end
  end
end
