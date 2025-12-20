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
    DeleteCollection,
    ReorderCollectionFeed,
    ChangeCollectionVisibility
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    CollectionCreated,
    FeedAddedToCollection,
    FeedRemovedFromCollection,
    CollectionUpdated,
    CollectionDeleted,
    CollectionFeedReordered,
    CollectionVisibilityChanged
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
               coll.is_default == true
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
          coll.is_default == true
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
          "default-1" => %{title: "All Subscriptions", is_default: true, feed_ids: []}
        }
      }

      # Try to create another default collection
      cmd = %CreateCollection{
        user_id: user_id,
        title: "All Podcasts",
        is_default: true,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      # Should return error for duplicate default collection
      assert match?({:error, :default_collection_already_exists}, result)
    end
  end

  describe "Create Collection Command" do
    test "valid title creates collection with UUID" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      cmd = %CreateCollection{
        user_id: user_id,
        title: "News",
        is_default: false,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionCreated{}, event)
      assert event.user_id == user_id
      assert event.title == "News"
      assert event.is_default == false
      # UUID length
      assert byte_size(event.collection_id) == 36
    end

    test "empty title returns error" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      cmd = %CreateCollection{
        user_id: user_id,
        title: "",
        is_default: false,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, _}, result)
    end

    test "non-default collections don't conflict" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      cmd = %CreateCollection{
        user_id: user_id,
        title: "More News",
        is_default: false,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?(%CollectionCreated{}, result)
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
          collection_id => %{title: "News", is_default: false, feed_ids: []}
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
          collection_id => %{title: "News", is_default: false, feed_ids: []}
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
          collection_id => %{title: "News", is_default: false, feed_ids: [feed]}
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
          collection_id => %{title: "News", is_default: false, feed_ids: []}
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
          collection_id => %{title: "News", is_default: false, feed_ids: []}
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
          collection_id => %{title: "News", is_default: false, feed_ids: []}
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
          collection_id => %{title: "All Subscriptions", is_default: true, feed_ids: []}
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
        is_default: false
      }

      updated_user = User.apply(user, event)

      assert collection_id in Map.keys(updated_user.collections)
      collection = updated_user.collections[collection_id]
      assert collection.title == "News"
      assert collection.is_default == false
    end

    test "apply FeedAddedToCollection adds feed to collection" do
      user_id = "user-123"
      feed = "base64-feed-url"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      event = %FeedAddedToCollection{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed
      }

      updated_user = User.apply(user, event)
      collection = updated_user.collections[collection_id]

      assert feed in collection.feed_ids
    end

    test "apply CollectionDeleted removes collection from aggregate" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      event = %CollectionDeleted{
        user_id: user_id,
        collection_id: collection_id,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      # CollectionDeleted removes the collection from the aggregate's collections map
      # The projection layer will handle the soft delete marker if needed
      assert collection_id not in Map.keys(updated_user.collections)
      assert map_size(updated_user.collections) == 0
    end
  end

  describe "Reorder Collection Feed Command" do
    test "reorders feed to new position" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()
      feed1 = "feed-1"
      feed2 = "feed-2"
      feed3 = "feed-3"

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: [feed1, feed2, feed3]
          }
        }
      }

      # Move feed3 to position 0 (first)
      cmd = %ReorderCollectionFeed{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: feed3,
        new_position: 0,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionFeedReordered{}, event)
      assert event.rss_source_feed == feed3
      assert event.new_position == 0
      assert event.feed_order == [feed3, feed1, feed2]
    end

    test "returns error if feed is not in collection" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: "feed-not-in-collection",
        new_position: 0,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :feed_not_in_collection}, result)
    end

    test "returns error if collection doesn't exist" do
      user_id = "user-123"

      user = %User{
        user_id: user_id,
        collections: %{}
      }

      cmd = %ReorderCollectionFeed{
        user_id: user_id,
        collection_id: "nonexistent",
        rss_source_feed: "feed-1",
        new_position: 0,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :collection_not_found}, result)
    end

    test "returns error for invalid position (negative)" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: "feed-1",
        new_position: -1,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :invalid_position}, result)
    end

    test "returns error for invalid position (out of bounds)" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: "feed-1",
        new_position: 5,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :invalid_position}, result)
    end

    test "apply CollectionFeedReordered updates feed order" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2", "feed-3"]
          }
        }
      }

      event = %CollectionFeedReordered{
        user_id: user_id,
        collection_id: collection_id,
        rss_source_feed: "feed-3",
        new_position: 0,
        feed_order: ["feed-3", "feed-1", "feed-2"],
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)
      collection = updated_user.collections[collection_id]

      assert collection.feed_ids == ["feed-3", "feed-1", "feed-2"]
    end
  end

  describe "ChangeCollectionVisibility Command" do
    test "makes collection public" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "My Collection", is_default: false, feed_ids: [], is_public: false}
        }
      }

      cmd = %ChangeCollectionVisibility{
        user_id: user_id,
        collection_id: collection_id,
        is_public: true,
        event_infos: %{device_id: "web", device_name: "Web Browser"}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionVisibilityChanged{}, event)
      assert event.user_id == user_id
      assert event.collection_id == collection_id
      assert event.is_public == true
    end

    test "makes collection private" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "My Collection", is_default: false, feed_ids: [], is_public: true}
        }
      }

      cmd = %ChangeCollectionVisibility{
        user_id: user_id,
        collection_id: collection_id,
        is_public: false,
        event_infos: %{}
      }

      event = User.execute(user, cmd)

      assert match?(%CollectionVisibilityChanged{}, event)
      assert event.is_public == false
    end

    test "returns error for non-existent collection" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      cmd = %ChangeCollectionVisibility{
        user_id: user_id,
        collection_id: "nonexistent",
        is_public: true,
        event_infos: %{}
      }

      result = User.execute(user, cmd)

      assert match?({:error, :collection_not_found}, result)
    end
  end

  describe "CollectionVisibilityChanged Event Application" do
    test "apply CollectionVisibilityChanged updates is_public to true" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "My Collection", is_default: false, feed_ids: [], is_public: false}
        }
      }

      event = %CollectionVisibilityChanged{
        user_id: user_id,
        collection_id: collection_id,
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.collections[collection_id].is_public == true
    end

    test "apply CollectionVisibilityChanged updates is_public to false" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "My Collection", is_default: false, feed_ids: [], is_public: true}
        }
      }

      event = %CollectionVisibilityChanged{
        user_id: user_id,
        collection_id: collection_id,
        is_public: false,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.collections[collection_id].is_public == false
    end

    test "apply CollectionVisibilityChanged doesn't affect other collections" do
      user_id = "user-123"
      collection_id = Ecto.UUID.generate()
      other_collection = Ecto.UUID.generate()

      user = %User{
        user_id: user_id,
        collections: %{
          collection_id => %{title: "Target", is_default: false, feed_ids: [], is_public: false},
          other_collection => %{title: "Other", is_default: false, feed_ids: [], is_public: false}
        }
      }

      event = %CollectionVisibilityChanged{
        user_id: user_id,
        collection_id: collection_id,
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated_user = User.apply(user, event)

      assert updated_user.collections[collection_id].is_public == true
      assert updated_user.collections[other_collection].is_public == false
    end

    test "apply CollectionVisibilityChanged handles missing collection gracefully" do
      user_id = "user-123"
      user = %User{user_id: user_id, collections: %{}}

      event = %CollectionVisibilityChanged{
        user_id: user_id,
        collection_id: "nonexistent",
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      # Should not crash, just return user unchanged
      updated_user = User.apply(user, event)

      assert updated_user == user
    end
  end
end
