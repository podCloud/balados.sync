defmodule BaladosSyncWeb.LiveWebSocket.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for WebSocket connections.

  Implements a per-connection rate limiting strategy to prevent abuse:
  - Each connection has a token bucket with configurable capacity
  - Tokens refill at a constant rate per second
  - Messages consume 1 token each
  - When tokens are exhausted, messages are rejected

  ## Configuration

  Default settings (10 req/sec with burst capacity of 20):
  - Bucket capacity: 20 tokens
  - Refill rate: 10 tokens per second

  These can be overridden in config:

      config :balados_sync_web, :rate_limiter,
        bucket_capacity: 20,
        refill_rate: 10
  """

  @type bucket :: %{
          tokens: float(),
          last_refill: integer()
        }

  # Default configuration
  @default_bucket_capacity 20
  @default_refill_rate 10

  @doc """
  Creates a new token bucket with full capacity.
  """
  @spec new_bucket() :: bucket()
  def new_bucket do
    %{
      tokens: bucket_capacity(),
      last_refill: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Attempts to consume a token from the bucket.

  Returns {:ok, updated_bucket} if a token was available,
  or {:error, :rate_limited, updated_bucket} if the bucket is empty.

  The bucket is always updated with refilled tokens before checking.
  """
  @spec consume(bucket()) :: {:ok, bucket()} | {:error, :rate_limited, bucket()}
  def consume(bucket) do
    # Refill tokens based on elapsed time
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - bucket.last_refill

    # Calculate tokens to add (refill_rate tokens per second = refill_rate/1000 per ms)
    tokens_to_add = elapsed_ms * refill_rate() / 1000

    # Update bucket with refilled tokens (capped at capacity)
    new_tokens = min(bucket.tokens + tokens_to_add, bucket_capacity())

    updated_bucket = %{
      tokens: new_tokens,
      last_refill: now
    }

    # Try to consume 1 token
    if new_tokens >= 1 do
      {:ok, %{updated_bucket | tokens: new_tokens - 1}}
    else
      {:error, :rate_limited, updated_bucket}
    end
  end

  @doc """
  Returns the current number of available tokens (for debugging/monitoring).
  """
  @spec available_tokens(bucket()) :: float()
  def available_tokens(bucket) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - bucket.last_refill
    tokens_to_add = elapsed_ms * refill_rate() / 1000
    min(bucket.tokens + tokens_to_add, bucket_capacity())
  end

  @doc """
  Returns the configured bucket capacity.
  """
  @spec bucket_capacity() :: pos_integer()
  def bucket_capacity do
    Application.get_env(:balados_sync_web, :rate_limiter, [])
    |> Keyword.get(:bucket_capacity, @default_bucket_capacity)
  end

  @doc """
  Returns the configured refill rate (tokens per second).
  """
  @spec refill_rate() :: pos_integer()
  def refill_rate do
    Application.get_env(:balados_sync_web, :rate_limiter, [])
    |> Keyword.get(:refill_rate, @default_refill_rate)
  end
end
