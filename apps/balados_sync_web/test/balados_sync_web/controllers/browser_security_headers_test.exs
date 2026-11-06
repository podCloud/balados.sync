defmodule BaladosSyncWeb.BrowserSecurityHeadersTest do
  use BaladosSyncWeb.ConnCase, async: true

  # Phoenix 1.8's put_secure_browser_headers sends a default CSP instead of
  # x-frame-options. Pages may only be framed by the same origin: an embeddable
  # player or widget would need its own pipeline with a wider frame-ancestors.
  test "browser pages forbid framing by other origins", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'self'"
    assert csp =~ "base-uri 'self'"
    assert get_resp_header(conn, "x-frame-options") == []
  end
end
