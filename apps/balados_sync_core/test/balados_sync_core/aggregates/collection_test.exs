defmodule BaladosSyncCore.Aggregates.CollectionTest do
  @moduledoc """
  Tests for the Collection aggregate.

  Tests the CQRS/ES implementation of collections, including:
  - Commands for managing collections and feeds
  - Event handling and aggregate state updates

  Note: The feed_not_subscribed validation is tested in the middleware test,
  not here, since it's handled by ValidateSubscription middleware.
  """

  use ExUnit.Case

  alias BaladosSyncCore.Aggregates.Collection

  alias BaladosSyncCore.Commands.{
    CreateCollection,
    AddFeedToCollection,
    RemoveFeedFromCollection,
    UpdateCollection,
    DeleteCollection,
    ReorderCollectionFeed,
    ChangeCollectionVisibility,
    SnapshotCollection
  }

  alias BaladosSyncCore.Events.{
    CollectionCreated,
    FeedAddedToCollection,
    FeedRemovedFromCollection,
    CollectionUpdated,
    CollectionDeleted,
    CollectionFeedReordered,
    CollectionVisibilityChanged,
    CollectionCheckpoint
  }

  describe "Create Collection Command" do
    test "valid title creates collection with UUID" do
      user_id = "user-123"
      state = %Collection{user_id: user_id, collections: %{}}

      cmd = %CreateCollection{
        user_id: user_id,
        title: "News",
        is_default: false,
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)

      assert match?(%CollectionCreated{}, event)
      assert event.user_id == user_id
      assert event.title == "News"
      assert event.is_default == false
      assert byte_size(event.collection_id) == 36
    end

    test "creates collection on new aggregate (user_id nil)" do
      state = %Collection{user_id: nil}

      cmd = %CreateCollection{
        user_id: "user-123",
        title: "News",
        is_default: true,
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)

      assert match?(%CollectionCreated{}, event)
      assert event.is_default == true
    end

    test "empty title returns error" do
      state = %Collection{user_id: "user-123", collections: %{}}

      cmd = %CreateCollection{
        user_id: "user-123",
        title: "",
        is_default: false,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :title_required}, result)
    end

    test "cannot have multiple default collections per user" do
      state = %Collection{
        user_id: "user-123",
        collections: %{
          "default-1" => %{title: "All Subscriptions", is_default: true, feed_ids: []}
        }
      }

      cmd = %CreateCollection{
        user_id: "user-123",
        title: "All Podcasts",
        is_default: true,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :default_collection_already_exists}, result)
    end

    test "non-default collections don't conflict" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      cmd = %CreateCollection{
        user_id: "user-123",
        title: "More News",
        is_default: false,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?(%CollectionCreated{}, result)
    end
  end

  describe "Add Feed to Collection Command" do
    test "adds feed to existing collection" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      cmd = %AddFeedToCollection{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-1",
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)

      assert match?(%FeedAddedToCollection{}, event)
      assert event.rss_source_feed == "feed-1"
    end

    test "returns error if collection doesn't exist" do
      state = %Collection{user_id: "user-123", collections: %{}}

      cmd = %AddFeedToCollection{
        user_id: "user-123",
        collection_id: "nonexistent-collection",
        rss_source_feed: "feed-1",
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :collection_not_found}, result)
    end
  end

  describe "Remove Feed from Collection Command" do
    test "removes feed from collection" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: ["feed-1"]}
        }
      }

      cmd = %RemoveFeedFromCollection{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-1",
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)
      assert match?(%FeedRemovedFromCollection{}, event)
      assert event.rss_source_feed == "feed-1"
    end

    test "returns error if collection doesn't exist" do
      state = %Collection{user_id: "user-123", collections: %{}}

      cmd = %RemoveFeedFromCollection{
        user_id: "user-123",
        collection_id: "nonexistent",
        rss_source_feed: "feed-1",
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :collection_not_found}, result)
    end
  end

  describe "Update Collection Command" do
    test "updates collection title" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      cmd = %UpdateCollection{
        user_id: "user-123",
        collection_id: collection_id,
        title: "Breaking News",
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)
      assert match?(%CollectionUpdated{}, event)
      assert event.title == "Breaking News"
    end

    test "prevents empty title update" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      cmd = %UpdateCollection{
        user_id: "user-123",
        collection_id: collection_id,
        title: "",
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, _}, result)
    end
  end

  describe "Delete Collection Command" do
    test "deletes collection when not default" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      cmd = %DeleteCollection{
        user_id: "user-123",
        collection_id: collection_id,
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)
      assert match?(%CollectionDeleted{}, event)
      assert event.collection_id == collection_id
    end

    test "returns error for default collection" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "All Subscriptions", is_default: true, feed_ids: []}
        }
      }

      cmd = %DeleteCollection{
        user_id: "user-123",
        collection_id: collection_id,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :cannot_delete_default_collection}, result)
    end

    test "returns error if collection doesn't exist" do
      state = %Collection{user_id: "user-123", collections: %{}}

      cmd = %DeleteCollection{
        user_id: "user-123",
        collection_id: "nonexistent",
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, _}, result)
    end
  end

  describe "Event Application (apply/2)" do
    test "apply CollectionCreated updates aggregate state" do
      state = %Collection{user_id: "user-123", collections: %{}}
      collection_id = Ecto.UUID.generate()

      event = %CollectionCreated{
        user_id: "user-123",
        collection_id: collection_id,
        title: "News",
        is_default: false
      }

      updated = Collection.apply(state, event)

      assert collection_id in Map.keys(updated.collections)
      collection = updated.collections[collection_id]
      assert collection.title == "News"
      assert collection.is_default == false
    end

    test "apply FeedAddedToCollection adds feed to collection" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      event = %FeedAddedToCollection{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-1"
      }

      updated = Collection.apply(state, event)
      collection = updated.collections[collection_id]
      assert "feed-1" in collection.feed_ids
    end

    test "apply CollectionDeleted removes collection from aggregate" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "News", is_default: false, feed_ids: []}
        }
      }

      event = %CollectionDeleted{
        user_id: "user-123",
        collection_id: collection_id,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Collection.apply(state, event)
      assert collection_id not in Map.keys(updated.collections)
      assert map_size(updated.collections) == 0
    end
  end

  describe "Reorder Collection Feed Command" do
    test "reorders feed to new position" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2", "feed-3"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-3",
        new_position: 0,
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)

      assert match?(%CollectionFeedReordered{}, event)
      assert event.feed_order == ["feed-3", "feed-1", "feed-2"]
    end

    test "returns error if feed is not in collection" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-not-in-collection",
        new_position: 0,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :feed_not_in_collection}, result)
    end

    test "returns error if collection doesn't exist" do
      state = %Collection{user_id: "user-123", collections: %{}}

      cmd = %ReorderCollectionFeed{
        user_id: "user-123",
        collection_id: "nonexistent",
        rss_source_feed: "feed-1",
        new_position: 0,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :collection_not_found}, result)
    end

    test "returns error for out-of-bounds position" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-1",
        new_position: 2,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :invalid_position}, result)
    end

    test "returns error for invalid position (negative)" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2"]
          }
        }
      }

      cmd = %ReorderCollectionFeed{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-1",
        new_position: -1,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :invalid_position}, result)
    end

    test "apply CollectionFeedReordered updates feed order" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            feed_ids: ["feed-1", "feed-2", "feed-3"]
          }
        }
      }

      event = %CollectionFeedReordered{
        user_id: "user-123",
        collection_id: collection_id,
        rss_source_feed: "feed-3",
        new_position: 0,
        feed_order: ["feed-3", "feed-1", "feed-2"],
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Collection.apply(state, event)
      collection = updated.collections[collection_id]
      assert collection.feed_ids == ["feed-3", "feed-1", "feed-2"]
    end
  end

  describe "ChangeCollectionVisibility Command" do
    test "makes collection public" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "My Collection", is_default: false, feed_ids: [], is_public: false}
        }
      }

      cmd = %ChangeCollectionVisibility{
        user_id: "user-123",
        collection_id: collection_id,
        is_public: true,
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)

      assert match?(%CollectionVisibilityChanged{}, event)
      assert event.is_public == true
    end

    test "makes collection private" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "Public Collection", is_default: false, feed_ids: [], is_public: true}
        }
      }

      cmd = %ChangeCollectionVisibility{
        user_id: "user-123",
        collection_id: collection_id,
        is_public: false,
        event_infos: %{}
      }

      event = Collection.execute(state, cmd)

      assert match?(%CollectionVisibilityChanged{}, event)
      assert event.is_public == false
    end

    test "returns error for non-existent collection" do
      state = %Collection{user_id: "user-123", collections: %{}}

      cmd = %ChangeCollectionVisibility{
        user_id: "user-123",
        collection_id: "nonexistent",
        is_public: true,
        event_infos: %{}
      }

      result = Collection.execute(state, cmd)
      assert match?({:error, :collection_not_found}, result)
    end
  end

  describe "CollectionVisibilityChanged Event Application" do
    test "apply CollectionVisibilityChanged updates is_public" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{title: "My Collection", is_default: false, feed_ids: [], is_public: false}
        }
      }

      event = %CollectionVisibilityChanged{
        user_id: "user-123",
        collection_id: collection_id,
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Collection.apply(state, event)
      assert updated.collections[collection_id].is_public == true
    end

    test "apply CollectionVisibilityChanged handles missing collection gracefully" do
      state = %Collection{user_id: "user-123", collections: %{}}

      event = %CollectionVisibilityChanged{
        user_id: "user-123",
        collection_id: "nonexistent",
        is_public: true,
        timestamp: DateTime.utc_now(),
        event_infos: %{}
      }

      updated = Collection.apply(state, event)
      assert updated == state
    end
  end

  describe "SnapshotCollection command" do
    test "emits CollectionCheckpoint with current state" do
      collection_id = Ecto.UUID.generate()

      state = %Collection{
        user_id: "user-123",
        collections: %{
          collection_id => %{
            title: "News",
            is_default: false,
            description: nil,
            color: nil,
            feed_ids: ["feed-1"],
            is_public: false
          }
        }
      }

      event = Collection.execute(state, %SnapshotCollection{user_id: "user-123"})

      assert %CollectionCheckpoint{} = event
      assert event.user_id == "user-123"
      assert Map.has_key?(event.collections, collection_id)
      assert event.collections[collection_id].feed_ids == ["feed-1"]
    end

    test "emits checkpoint with empty collections on nil state" do
      state = %Collection{user_id: "user-123", collections: nil}

      event = Collection.execute(state, %SnapshotCollection{user_id: "user-123"})

      assert %CollectionCheckpoint{} = event
      assert event.collections == %{}
    end
  end

  describe "CollectionCheckpoint apply" do
    test "restores full state including user_id" do
      state = %Collection{user_id: nil, collections: nil}

      collections = %{
        "col-1" => %{
          title: "News",
          is_default: true,
          description: nil,
          color: "#ff0000",
          feed_ids: ["feed-1", "feed-2"],
          is_public: false
        }
      }

      event = %CollectionCheckpoint{
        user_id: "user-123",
        collections: collections,
        timestamp: DateTime.utc_now()
      }

      updated = Collection.apply(state, event)

      assert updated.user_id == "user-123"
      assert updated.collections == collections
    end
  end
end
