defmodule BaladosSyncWeb.AdminHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  test "the RSS utility page shows the proxy URL formats with literal braces" do
    html = rendered_to_string(BaladosSyncWeb.AdminHTML.rss_utility(%{}))

    assert html =~ "/api/v1/rss/proxy/{encoded_feed}/{encoded_episode}"
    assert html =~ "/api/v1/rss/proxy/{encoded_feed}/{base64(guid + \",\" + enclosure_url)}"
    assert html =~ "/api/v1/rss/proxy/{encoded_feed}/{encoded_episode_id}"
  end
end
