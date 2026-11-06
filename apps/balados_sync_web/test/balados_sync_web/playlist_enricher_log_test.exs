defmodule BaladosSyncWeb.PlaylistEnricherLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BaladosSyncWeb.PlaylistEnricher

  test "a failed feed fetch logs the URL without credentials or query token" do
    url = "http://alice:s3cret@127.0.0.1/enricher.xml?token=t0ken"

    log =
      capture_log([level: :warning], fn ->
        PlaylistEnricher.fetch_feeds_parallel([url])
      end)

    assert log =~ "Failed to fetch feed http://127.0.0.1/enricher.xml"
    refute log =~ "s3cret"
    refute log =~ "t0ken"
  end
end
