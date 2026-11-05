defmodule BaladosSyncWeb.RssCacheConfigTest do
  @moduledoc """
  Pins the cache configuration that used to be implicit (Cachex 3 `ttl:` and
  `limit:` options): every entry expires after 5 minutes and the cache is bounded
  to 500 entries by a scheduled LRW policy.
  """

  use ExUnit.Case, async: false

  require Cachex.Spec
  import Cachex.Spec

  @cache :rss_feed_cache
  @five_minutes :timer.minutes(5)

  setup do
    on_exit(fn -> Cachex.clear(@cache) end)
    :ok
  end

  test "web RssCache.put/2 sets a 5-minute expiration" do
    BaladosSyncWeb.RssCache.put({:test, :web}, "value")
    assert {:ok, ttl} = Cachex.ttl(@cache, {:test, :web})
    assert is_integer(ttl) and ttl > @five_minutes - 5_000 and ttl <= @five_minutes
  end

  test "core RssCache.put/2 sets a 5-minute expiration" do
    BaladosSyncCore.RssCache.put({:test, :core}, "value")
    assert {:ok, ttl} = Cachex.ttl(@cache, {:test, :core})
    assert is_integer(ttl) and ttl > @five_minutes - 5_000 and ttl <= @five_minutes
  end

  test "the cache is bounded to 500 entries by a scheduled limit hook" do
    {:ok, cache(hooks: hooks_record)} = Cachex.inspect(@cache, :cache)
    # hooks(pre: [...], post: [...], ...) : the scheduled limit is not a pre/post
    # hook, so look through every list of the record
    all_hooks = hooks_record |> Tuple.to_list() |> tl() |> List.flatten()

    assert Enum.any?(all_hooks, fn
             hook(module: Cachex.Limit.Scheduled, args: {500, _, _}) -> true
             _ -> false
           end)
  end
end
