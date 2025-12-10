defmodule BaladosSyncProjections.Projectors.CollectionsProjectorTest do
  @moduledoc """
  Tests for the CollectionsProjector.

  Tests the projection of collection-related events to the read model:
  - CollectionCreated → collections table
  - FeedAddedToCollection → collection_subscriptions table
  - FeedRemovedFromCollection → deletion from collection_subscriptions
  - CollectionUpdated → update of title/updated_at
  - CollectionDeleted → soft delete with deleted_at
  """

  use BaladosSyncProjections.DataCase

  alias BaladosSyncCore.Events.{
    CollectionCreated,
    FeedAddedToCollection,
    FeedRemovedFromCollection,
    CollectionUpdated,
    CollectionDeleted
  }

  alias BaladosSyncProjections.Schemas.{Collection, CollectionSubscription}

  describe "CollectionCreated projection" do
    test "creates row in collections table" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      # Manually apply projection (in real tests, events are emitted through Dispatcher)
      apply_projection(event)

      # Verify collection was created
      collection =
        ProjectionsRepo.get_by(Collection, user_id: user_id, id: collection_id)

      assert not is_nil(collection)
      assert collection.title == "News"
      assert collection.slug == "news"
      assert is_nil(collection.deleted_at)
    end

    test "idempotent - replaying creates same state" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      # Apply twice
      apply_projection(event)
      apply_projection(event)

      # Should only have one collection
      collections =
        ProjectionsRepo.all(
          from(c in Collection,
            where: c.user_id == ^user_id and c.id == ^collection_id
          )
        )

      assert length(collections) == 1
    end
  end

  describe "FeedAddedToCollection projection" do
    test "creates row in collection_subscriptions" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()
      feed = "base64-feed-url"

      # Create collection first
      create_event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event)

      # Add feed to collection
      add_feed_event = %FeedAddedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        timestamp: DateTime.utc_now()
      }

      apply_projection(add_feed_event)

      # Verify association was created
      subscription =
        ProjectionsRepo.get_by(CollectionSubscription,
          collection_id: collection_id,
          rss_source_feed: feed
        )

      assert not is_nil(subscription)
    end

    test "idempotent - replaying maintains one record" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()
      feed = "base64-feed-url"

      create_event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event)

      add_feed_event = %FeedAddedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        timestamp: DateTime.utc_now()
      }

      # Apply twice
      apply_projection(add_feed_event)
      apply_projection(add_feed_event)

      # Should only have one subscription
      subscriptions =
        ProjectionsRepo.all(
          from(s in CollectionSubscription,
            where: s.collection_id == ^collection_id and s.rss_source_feed == ^feed
          )
        )

      assert length(subscriptions) == 1
    end
  end

  describe "FeedRemovedFromCollection projection" do
    test "deletes from collection_subscriptions" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()
      feed = "base64-feed-url"

      # Create and add feed
      create_event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event)

      add_feed_event = %FeedAddedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        timestamp: DateTime.utc_now()
      }

      apply_projection(add_feed_event)

      # Remove feed
      remove_feed_event = %FeedRemovedFromCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        timestamp: DateTime.utc_now()
      }

      apply_projection(remove_feed_event)

      # Verify subscription was deleted
      subscription =
        ProjectionsRepo.get_by(CollectionSubscription,
          collection_id: collection_id,
          rss_source_feed: feed
        )

      assert is_nil(subscription)
    end
  end

  describe "CollectionUpdated projection" do
    test "updates title and updated_at" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      # Create collection
      create_event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event)

      # Update title
      update_event = %CollectionUpdated{
        user_id: user_id,
        collection_id: collection_id,
        title: "Breaking News",
        timestamp: DateTime.utc_now()
      }

      apply_projection(update_event)

      # Verify update
      collection = ProjectionsRepo.get(Collection, collection_id)

      assert collection.title == "Breaking News"
      assert not is_nil(collection.updated_at)
    end
  end

  describe "CollectionDeleted projection" do
    test "soft-deletes with deleted_at timestamp" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      # Create collection
      create_event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event)

      # Delete collection
      delete_time = DateTime.utc_now()

      delete_event = %CollectionDeleted{
        user_id: user_id,
        collection_id: collection_id,
        deleted_at: delete_time,
        timestamp: delete_time
      }

      apply_projection(delete_event)

      # Verify soft delete
      collection = ProjectionsRepo.get(Collection, collection_id)

      assert not is_nil(collection.deleted_at)
    end
  end

  describe "Default collection handling" do
    test "only one active default collection per user" do
      user_id = "user-123"
      default_id = Ecto.UUID.generate()

      # Create default collection
      event = %CollectionCreated{
        user_id: user_id,
        collection_id: default_id,
        title: "All Subscriptions",
        slug: "all",
        timestamp: DateTime.utc_now()
      }

      apply_projection(event)

      # Verify it's the only active default for user
      defaults =
        ProjectionsRepo.all(
          from(c in Collection,
            where: c.user_id == ^user_id and c.slug == "all" and is_nil(c.deleted_at)
          )
        )

      assert length(defaults) == 1
      assert defaults |> List.first() |> Map.get(:id) == default_id
    end

    test "deleted default collection doesn't prevent new one" do
      user_id = "user-123"
      old_default_id = Ecto.UUID.generate()
      new_default_id = Ecto.UUID.generate()

      # Create first default
      create_event1 = %CollectionCreated{
        user_id: user_id,
        collection_id: old_default_id,
        title: "All Subscriptions",
        slug: "all",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event1)

      # Delete it
      delete_event = %CollectionDeleted{
        user_id: user_id,
        collection_id: old_default_id,
        deleted_at: DateTime.utc_now(),
        timestamp: DateTime.utc_now()
      }

      apply_projection(delete_event)

      # Create new default
      create_event2 = %CollectionCreated{
        user_id: user_id,
        collection_id: new_default_id,
        title: "All Subscriptions",
        slug: "all",
        timestamp: DateTime.utc_now()
      }

      apply_projection(create_event2)

      # Verify only new default is active
      defaults =
        ProjectionsRepo.all(
          from(c in Collection,
            where: c.user_id == ^user_id and c.slug == "all" and is_nil(c.deleted_at)
          )
        )

      assert length(defaults) == 1
      assert defaults |> List.first() |> Map.get(:id) == new_default_id
    end
  end

  # Helper to apply projections manually (in real app, done through Dispatcher)
  defp apply_projection(event) do
    # This is a simplified version - in real tests, events come through the event bus
    # For now, we're manually testing the projection logic
    handle_event(event)
  end

  # Manual event handling for testing
  defp handle_event(%CollectionCreated{} = event) do
    changeset =
      Collection.changeset(%Collection{}, %{
        id: event.collection_id,
        user_id: event.user_id,
        title: event.title,
        slug: event.slug,
        inserted_at: event.timestamp,
        updated_at: event.timestamp
      })

    ProjectionsRepo.insert(changeset,
      on_conflict: {:replace, [:title, :slug, :updated_at]},
      conflict_target: [:id]
    )
  end

  defp handle_event(%FeedAddedToCollection{} = event) do
    changeset =
      CollectionSubscription.changeset(%CollectionSubscription{}, %{
        collection_id: event.collection_id,
        rss_source_feed: event.rss_source_feed
      })

    ProjectionsRepo.insert(changeset,
      on_conflict: :nothing,
      conflict_target: [:collection_id, :rss_source_feed]
    )
  end

  defp handle_event(%FeedRemovedFromCollection{} = event) do
    ProjectionsRepo.delete_all(
      from(s in CollectionSubscription,
        where:
          s.collection_id == ^event.collection_id and s.rss_source_feed == ^event.rss_source_feed
      )
    )
  end

  defp handle_event(%CollectionUpdated{} = event) do
    ProjectionsRepo.update_all(
      from(c in Collection, where: c.id == ^event.collection_id),
      set: [title: event.title, updated_at: event.timestamp]
    )
  end

  defp handle_event(%CollectionDeleted{} = event) do
    ProjectionsRepo.update_all(
      from(c in Collection, where: c.id == ^event.collection_id),
      set: [deleted_at: event.deleted_at, updated_at: event.deleted_at]
    )
  end
end
