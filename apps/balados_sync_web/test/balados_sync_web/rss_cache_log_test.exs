defmodule BaladosSyncWeb.RssCacheLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BaladosSyncWeb.RssCache

  test "a blocked fetch logs the feed URL without credentials or query token" do
    url = "http://alice:s3cret@127.0.0.1/private.xml?token=t0ken"

    log =
      capture_log([level: :warning], fn ->
        assert {:error, _} = RssCache.fetch_feed(url)
      end)

    assert log =~ "http://127.0.0.1/private.xml"
    refute log =~ "s3cret"
    refute log =~ "t0ken"
  end
end
