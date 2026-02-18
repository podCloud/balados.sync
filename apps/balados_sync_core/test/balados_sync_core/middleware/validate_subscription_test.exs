defmodule BaladosSyncCore.Middleware.ValidateSubscriptionTest do
  # async: false is required because tests use Application.put_env/3 to inject
  # mock repos, which is global state. Running async could cause test interference.
  use ExUnit.Case, async: false

  alias BaladosSyncCore.Middleware.ValidateSubscription
  alias BaladosSyncCore.Commands.{AddFeedToCollection, Subscribe}

  # Mock repo that always returns nil (feed not subscribed)
  defmodule NotSubscribedRepo do
    def one(_query, _opts), do: nil
  end

  # Mock repo that returns a subscription id (feed is subscribed)
  defmodule SubscribedRepo do
    def one(_query, _opts), do: Ecto.UUID.generate()
  end

  # Mock repo that raises a database error
  defmodule ErrorRepo do
    def one(_query, _opts), do: raise(DBConnection.ConnectionError, "connection refused")
  end

  describe "before_dispatch/1" do
    test "passes through non-AddFeedToCollection commands unchanged" do
      pipeline = %Commanded.Middleware.Pipeline{
        command: %Subscribe{
          user_id: "user-1",
          rss_source_feed: "feed-1",
          rss_source_id: "source-1"
        }
      }

      result = ValidateSubscription.before_dispatch(pipeline)

      assert result == pipeline
    end

    test "halts with :feed_not_subscribed when feed is not subscribed" do
      Application.put_env(:balados_sync_core, :projections_repo, NotSubscribedRepo)

      pipeline = %Commanded.Middleware.Pipeline{
        command: %AddFeedToCollection{
          user_id: "user-1",
          collection_id: "col-1",
          rss_source_feed: "feed-1"
        }
      }

      result = ValidateSubscription.before_dispatch(pipeline)

      assert %Commanded.Middleware.Pipeline{
               halted: true,
               response: {:error, :feed_not_subscribed}
             } = result
    after
      Application.delete_env(:balados_sync_core, :projections_repo)
    end

    test "passes through when feed is subscribed" do
      Application.put_env(:balados_sync_core, :projections_repo, SubscribedRepo)

      pipeline = %Commanded.Middleware.Pipeline{
        command: %AddFeedToCollection{
          user_id: "user-1",
          collection_id: "col-1",
          rss_source_feed: "feed-1"
        }
      }

      result = ValidateSubscription.before_dispatch(pipeline)

      refute result.halted
      assert result == pipeline
    after
      Application.delete_env(:balados_sync_core, :projections_repo)
    end

    test "halts with :subscription_check_failed on database error" do
      Application.put_env(:balados_sync_core, :projections_repo, ErrorRepo)

      pipeline = %Commanded.Middleware.Pipeline{
        command: %AddFeedToCollection{
          user_id: "user-1",
          collection_id: "col-1",
          rss_source_feed: "feed-1"
        }
      }

      result = ValidateSubscription.before_dispatch(pipeline)

      assert %Commanded.Middleware.Pipeline{
               halted: true,
               response: {:error, :subscription_check_failed}
             } = result
    after
      Application.delete_env(:balados_sync_core, :projections_repo)
    end
  end

  describe "after_dispatch/1" do
    test "passes through unchanged" do
      pipeline = %Commanded.Middleware.Pipeline{}
      assert ValidateSubscription.after_dispatch(pipeline) == pipeline
    end
  end

  describe "after_failure/1" do
    test "passes through unchanged" do
      pipeline = %Commanded.Middleware.Pipeline{}
      assert ValidateSubscription.after_failure(pipeline) == pipeline
    end
  end
end
