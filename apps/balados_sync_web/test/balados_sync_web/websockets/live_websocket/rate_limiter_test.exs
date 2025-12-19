defmodule BaladosSyncWeb.LiveWebSocket.RateLimiterTest do
  @moduledoc """
  Tests for the token bucket rate limiter.
  """

  use ExUnit.Case, async: true

  alias BaladosSyncWeb.LiveWebSocket.RateLimiter

  describe "new_bucket/0" do
    test "creates bucket with full capacity" do
      bucket = RateLimiter.new_bucket()

      assert bucket.tokens == RateLimiter.bucket_capacity()
      assert is_integer(bucket.last_refill)
    end
  end

  describe "consume/1" do
    test "consumes token when available" do
      bucket = RateLimiter.new_bucket()
      initial_tokens = bucket.tokens

      assert {:ok, new_bucket} = RateLimiter.consume(bucket)
      assert new_bucket.tokens < initial_tokens
    end

    test "returns error when bucket is empty" do
      # Create a bucket with 0 tokens
      bucket = %{tokens: 0.0, last_refill: System.monotonic_time(:millisecond)}

      assert {:error, :rate_limited, _new_bucket} = RateLimiter.consume(bucket)
    end

    test "refills tokens over time" do
      # Create a bucket that was last refilled 100ms ago with 0 tokens
      bucket = %{
        tokens: 0.0,
        last_refill: System.monotonic_time(:millisecond) - 100
      }

      # Should have refilled some tokens (100ms * 10/1000 = 1 token)
      assert {:ok, new_bucket} = RateLimiter.consume(bucket)
      # After consuming 1, should have ~0 tokens
      assert new_bucket.tokens >= 0
    end

    test "caps tokens at bucket capacity" do
      # Create a bucket that was last refilled a long time ago
      bucket = %{
        tokens: 0.0,
        last_refill: System.monotonic_time(:millisecond) - 10_000
      }

      {:ok, new_bucket} = RateLimiter.consume(bucket)

      # Should be capped at capacity minus 1 (for the consumed token)
      assert new_bucket.tokens <= RateLimiter.bucket_capacity() - 1
    end

    test "burst capacity allows multiple rapid messages" do
      bucket = RateLimiter.new_bucket()
      capacity = RateLimiter.bucket_capacity()

      # Should be able to send burst_capacity messages rapidly
      {final_bucket, success_count} =
        Enum.reduce(1..capacity, {bucket, 0}, fn _i, {b, count} ->
          case RateLimiter.consume(b) do
            {:ok, new_b} -> {new_b, count + 1}
            {:error, :rate_limited, new_b} -> {new_b, count}
          end
        end)

      assert success_count == capacity
      assert final_bucket.tokens < 1
    end

    test "rejects message after burst is exhausted" do
      bucket = RateLimiter.new_bucket()
      capacity = RateLimiter.bucket_capacity()

      # Exhaust the bucket
      {exhausted_bucket, _} =
        Enum.reduce(1..capacity, {bucket, 0}, fn _i, {b, count} ->
          {:ok, new_b} = RateLimiter.consume(b)
          {new_b, count + 1}
        end)

      # Next message should be rate limited
      assert {:error, :rate_limited, _} = RateLimiter.consume(exhausted_bucket)
    end
  end

  describe "available_tokens/1" do
    test "returns current token count with refill" do
      bucket = %{
        tokens: 5.0,
        last_refill: System.monotonic_time(:millisecond) - 100
      }

      available = RateLimiter.available_tokens(bucket)

      # Should have 5 + (100ms * 10/1000) = ~6 tokens
      assert available >= 5.0
      assert available <= RateLimiter.bucket_capacity()
    end
  end

  describe "configuration" do
    test "bucket_capacity returns configured or default value" do
      # Should return a positive integer
      assert RateLimiter.bucket_capacity() > 0
      assert is_integer(RateLimiter.bucket_capacity())
    end

    test "refill_rate returns configured or default value" do
      # Should return a positive integer
      assert RateLimiter.refill_rate() > 0
      assert is_integer(RateLimiter.refill_rate())
    end
  end
end
