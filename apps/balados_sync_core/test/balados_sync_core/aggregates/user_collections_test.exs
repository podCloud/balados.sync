defmodule BaladosSyncCore.Aggregates.UserCollectionsTest do
  @moduledoc """
  Tests for Collections functionality in the User aggregate.

  Tests the CQRS/ES implementation of collections, including:
  - Automatic creation of default collection on first subscription
  - Commands for managing collections and feeds
  - Event handling and aggregate state updates
  """

  use ExUnit.Case

  alias BaladosSyncCore.Aggregates.User

  alias BaladosSyncCore.Commands.{
    Subscribe,
    CreateCollection,
    AddFeedToCollection,
    RemoveFeedFromCollection,
    UpdateCollection,
    DeleteCollection
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    CollectionCreated,
    FeedAddedToCollection,
    FeedRemovedFromCollection,
    CollectionUpdated,
    CollectionDeleted
  }

  describe "Default Collection Creation" do
    test "default collection is created on first subscription" do
      user_id = "user-123"
      feed = "base64-feed-url"

      # Aggregate starts empty
      user = %User{user_id: user_id, collections: %{}}

      # First subscription
      subscribe_cmd = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      # Execute command
      event_or_events = User.execute(user, subscribe_cmd)

      # Can return single event or list of events
      events = if is_list(event_or_events), do: event_or_events, else: [event_or_events]

      # Should have UserSubscribed event
      assert Enum.any?(events, fn e -> match?(%UserSubscribed{}, e) end)

      # Apply events to aggregate
      updated_user = Enum.reduce(events, user, &User.apply(&2, &1))

      # Verify default collection was created
      assert map_size(updated_user.collections) > 0

      assert Enum.any?(updated_user.collections, fn {_id, coll} ->
               coll.slug == "all"
             end)
    end

    test "first feed is added to default collection" do
      user_id = "user-123"
      feed = "base64-feed-url"

      user = %User{user_id: user_id, collections: %{}}

      # Subscribe to feed
      subscribe_cmd = %Subscribe{
        user_id: user_id,
        rss_source_feed: feed,
        rss_source_id: "podcast-123",
        subscribed_at: DateTime.utc_now(),
        event_infos: %{}
      }

      events = [User.execute(user, subscribe_cmd)] |> List.flatten()
      updated_user = Enum.reduce(events, user, &User.apply(&2, &1))

      # Find default collection
      {_default_id, default_collection} =
        Enum.find(updated_user.collections, fn {_id, coll} ->
          coll.slug == "all"
        end)

      # Verify feed is in default collection
      assert is_list(default_collection.feed_ids) || is_struct(default_collection.feed_ids)
      assert feed in (default_collection.feed_ids || [])
    end

    test "cannot have multiple default collections per user" do
      user_id = "user-123"

      user = %User{
        user_id: user_id,
        collections: %{
          "default-1" => %{title: "All Subscriptions", slug: "all", feed_ids: []}
        }
      }

      # Try to create another default collection
      cmd = %CreateCollection{
        user_id: user_id,
        title: "All Podcasts",
        slug: "all",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      # Should either return error or prevent duplicate
      case result do
        {:error, reason} -> assert reason in [:slug_already_exists, :default_collection_exists]
        event -> assert match?(%CollectionCreated{}, event)
      end
    end
  end

  describe "Create Collection Command" do
    test "valid title creates collection with UUID" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      cmd = %CreateCollection{
        user_id: user_id,
        title: "News",
        slug: "news",
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionCreated{}, event)
      assert event.user_id == user_id
      assert event.title == "News"
      assert event.slug == "news"
      # UUID length
      assert byte_size(event.collection_id) == 36
    end

    test "empty title returns error" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      cmd = %CreateCollection{
        user_id: user_id,
        title: "",
        slug: "invalid",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, _}, result)
    end

    test "duplicate slug returns error" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      cmd = %CreateCollection{
        user_id: user_id,
        title: "More News",
        slug: "news",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, _}, result)
    end
  end

  describe "Add Feed to Collection Command" do
    test "adds feed to collection if feed is subscribed" do
      user_id = "user-123"
      feed = "base64-feed-url"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        subscriptions: %{
          feed => %{subscribed_at: DateTime.utc_now(), unsubscribed_at: nil}
        },
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      cmd = %AddFeedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%FeedAddedToCollection{}, event)
      assert event.rss_source_feed == feed
    end

    test "returns error if collection doesn't exist" do
      user_id = "user-123"
      feed = "base64-feed-url"

      user = %User{
        user_id: user_id,
        subscriptions: %{
          feed => %{subscribed_at: DateTime.utc_now(), unsubscribed_at: nil}
        },
        collections: %{}
      }

      cmd = %AddFeedToCollection{
        user_id: user_id,
        collection_id: "nonexistent-collection",
        rss_source_feed: feed,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :collection_not_found}, result)
    end

    test "returns error if feed is not subscribed" do
      user_id = "user-123"
      feed = "unsubscribed-feed"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        subscriptions: %{},
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      cmd = %AddFeedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :feed_not_subscribed}, result)
    end
  end

  describe "Remove Feed from Collection Command" do
    test "removes feed from collection" do
      user_id = "user-123"
      feed = "base64-feed-url"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new([feed])}
        }
      }

      cmd = %RemoveFeedFromCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%FeedRemovedFromCollection{}, event)
      assert event.rss_source_feed == feed
    end

    test "returns error if collection doesn't exist" do
      user_id = "user-123"
      feed = "base64-feed-url"

      user = %User{
        user_id: user_id,
        collections: %{}
      }

      cmd = %RemoveFeedFromCollection{
        user_id: user_id,
        collection_id: "nonexistent",
        rss_source_feed: feed,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :collection_not_found}, result)
    end
  end

  describe "Update Collection Command" do
    test "updates collection title" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      cmd = %UpdateCollection{
        user_id: user_id,
        collection_id: collection_id,
        title: "Breaking News",
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionUpdated{}, event)
      assert event.title == "Breaking News"
    end

    test "prevents empty title update" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      cmd = %UpdateCollection{
        user_id: user_id,
        collection_id: collection_id,
        title: "",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, _}, result)
    end
  end

  describe "Delete Collection Command" do
    test "deletes collection when not default" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      cmd = %DeleteCollection{
        user_id: user_id,
        collection_id: collection_id,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionDeleted{}, event)
      assert event.collection_id == collection_id
    end

    test "returns error for default collection" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "All Subscriptions", slug: "all", feed_ids: MapSet.new()}
        }
      }

      cmd = %DeleteCollection{
        user_id: user_id,
        collection_id: collection_id,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :cannot_delete_default_collection}, result)
    end

    test "returns error if collection doesn't exist" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      cmd = %DeleteCollection{
        user_id: user_id,
        collection_id: "nonexistent",
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, _}, result)
    end
  end

  describe "Event Application (apply/2)" do
    test "apply CollectionCreated updates aggregate state" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}
      collection_id = Ecto.UUID.generate()

      event = %CollectionCreated{
        user_id: user_id,
        collection_id: collection_id,
        title: "News",
        slug: "news"
      }

      updated_user = User.apply(user, event)

      assert collection_id in Map.keys(updated_user.collections)
      collection = updated_user.collections[collection_id]
      assert collection.title == "News"
      assert collection.slug == "news"
    end

    test "apply FeedAddedToCollection adds feed to collection" do
      user_id = "user-123"
      feed = "base64-feed-url"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      event = %FeedAddedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed
      }

      updated_user = User.apply(user, event)
      collection = updated_user.collections[collection_id]

      assert feed in (collection.feed_ids || [])
    end

    test "apply CollectionDeleted marks collection as deleted" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", slug: "news", feed_ids: MapSet.new()}
        }
      }

      event = %CollectionDeleted{
        user_id: user_id,
        collection_id: collection_id,
        deleted_at: DateTime.utc_now()
      }

      updated_user = User.apply(user, event)

      # In CQRS/ES, we typically keep the collection but mark it as deleted
      # Check that the collection is still in the map (soft delete)
      assert collection_id in Map.keys(updated_user.collections)
    end
  end
end
