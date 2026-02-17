defmodule BaladosSyncCore.Middleware.ValidateSubscriptionTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.Middleware.ValidateSubscription
  alias BaladosSyncCore.Commands.Subscribe

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
