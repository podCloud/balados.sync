defmodule BaladosSyncCore.SafeHttpTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.SafeHttp

  # Every request goes through Req.Test: no network. Host validation still
  # runs on the URL (and on every redirect target) before Req is called.
  defp get(url, opts \\ []),
    do: SafeHttp.get(url, Keyword.put(opts, :req_options, plug: {Req.Test, __MODULE__}))

  defp stub(fun), do: Req.Test.stub(__MODULE__, fun)

  defp redirect(conn, status, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(status, "")
  end

  test "returns the body of a 200 response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 200, "<rss/>") end)
    assert {:ok, "<rss/>"} = get("https://feeds.example.org/feed.xml")
  end

  test "returns {:http_error, status} for a non-200 response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 404, "nope") end)
    assert {:error, {:http_error, 404}} = get("https://feeds.example.org/feed.xml")
  end

  test "blocks a private initial URL without making a request" do
    stub(fn _conn -> flunk("no request expected") end)
    assert {:error, :url_blocked} = get("http://127.0.0.1:4000/feed.xml")
    assert {:error, :url_blocked} = get("http://localhost/feed.xml")
  end

  for status <- [301, 302, 303, 307, 308] do
    test "follows a #{status} redirect to a public URL" do
      stub(fn
        %{request_path: "/old"} = conn ->
          redirect(conn, unquote(status), "https://cdn.example.net/new")

        %{request_path: "/new"} = conn ->
          Plug.Conn.send_resp(conn, 200, "moved")
      end)

      assert {:ok, "moved"} = get("https://feeds.example.org/old")
    end
  end

  test "follows a redirect to a public URL on another host" do
    stub(fn
      %{request_path: "/old"} = conn ->
        redirect(conn, 301, "https://cdn.example.net/new")

      %{host: "cdn.example.net", request_path: "/new"} = conn ->
        Plug.Conn.send_resp(conn, 200, "moved")
    end)

    assert {:ok, "moved"} = get("https://feeds.example.org/old")
  end

  test "resolves a relative Location against the current URL" do
    stub(fn
      %{request_path: "/a/feed"} = conn -> redirect(conn, 302, "../b/feed")
      %{request_path: "/b/feed"} = conn -> Plug.Conn.send_resp(conn, 200, "relative")
    end)

    assert {:ok, "relative"} = get("https://feeds.example.org/a/feed")
  end

  for target <- [
        "http://169.254.169.254/latest/meta-data/",
        "http://127.0.0.1:4000/admin",
        "http://10.0.0.5/internal",
        "http://localhost/",
        "http://[::ffff:169.254.169.254]/latest/",
        "http://0.0.0.0:4000/",
        "http://localhost./",
        "file:///etc/passwd"
      ] do
    test "blocks a redirect to #{target}" do
      stub(fn
        %{request_path: "/feed"} = conn -> redirect(conn, 302, unquote(target))
        _conn -> flunk("the blocked redirect target must not be requested")
      end)

      assert {:error, :url_blocked} = get("https://feeds.example.org/feed")
    end
  end

  test "follows exactly 5 redirects and refuses the 6th" do
    test_pid = self()

    stub(fn conn ->
      send(test_pid, :hit)
      redirect(conn, 302, "https://feeds.example.org/loop")
    end)

    assert {:error, :too_many_redirects} = get("https://feeds.example.org/loop")
    # the initial request plus 5 followed redirects
    for _ <- 1..6, do: assert_received(:hit)
    refute_received :hit
  end

  test "a chain of exactly 5 redirects succeeds" do
    stub(fn %{request_path: "/r" <> n} = conn ->
      case String.to_integer(n) do
        5 -> Plug.Conn.send_resp(conn, 200, "end of chain")
        i -> redirect(conn, 302, "/r#{i + 1}")
      end
    end)

    assert {:ok, "end of chain"} = get("https://feeds.example.org/r0")
  end

  test "a redirect without Location is an HTTP error" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 302, "") end)
    assert {:error, {:http_error, 302}} = get("https://feeds.example.org/feed")
  end

  test "transport errors become {:network_error, reason}, without retries" do
    test_pid = self()

    stub(fn conn ->
      send(test_pid, :hit)
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, {:network_error, :timeout}} = get("https://feeds.example.org/feed")
    assert_received :hit
    refute_received :hit
  end

  test "a Finch pool checkout failure is returned as a network error, not raised" do
    stub(fn _conn ->
      raise RuntimeError, "Finch was unable to provide a connection within the timeout"
    end)

    assert {:error, {:network_error, %RuntimeError{message: "Finch was unable" <> _}}} =
             get("https://feeds.example.org/feed")
  end

  test "any other RuntimeError is not swallowed" do
    stub(fn _conn -> raise RuntimeError, "a programming error" end)

    assert_raise RuntimeError, "a programming error", fn ->
      get("https://feeds.example.org/feed")
    end
  end

  test "passes the body through untouched and identifies Balados" do
    gz = :zlib.gzip("<rss/>")

    stub(fn conn ->
      assert Plug.Conn.get_req_header(conn, "accept-encoding") == []
      assert [ua] = Plug.Conn.get_req_header(conn, "user-agent")
      assert ua =~ ~r/^Balados\//

      conn
      |> Plug.Conn.put_resp_header("content-encoding", "gzip")
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, gz)
    end)

    assert {:ok, ^gz} = get("https://feeds.example.org/feed")
  end

  test "sends the given headers" do
    stub(fn conn ->
      assert Plug.Conn.get_req_header(conn, "cache-control") == ["no-cache"]
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert {:ok, "ok"} =
             get("https://feeds.example.org/feed", headers: [{"cache-control", "no-cache"}])
  end

  test "a request-target error does not carry the URL path and query" do
    # Mint rejects a target with a space or quote that UrlValidator accepts and
    # puts the raw path+query in the reason; callers log inspect(reason).
    adapter = fn request ->
      {request,
       %Req.HTTPError{protocol: :http1, reason: {:invalid_request_target, "/rss?token=SEKRET a"}}}
    end

    assert {:error, {:network_error, :invalid_request_target}} =
             SafeHttp.get("https://feeds.example.org/rss?token=SEKRET a",
               req_options: [adapter: adapter]
             )
  end

  describe "loggable/1" do
    test "removes user:pass@ credentials" do
      assert SafeHttp.loggable("https://alice:s3cret@feeds.example.com/rss") ==
               "https://feeds.example.com/rss"
    end

    test "drops the query string and fragment, where private-feed tokens live" do
      assert SafeHttp.loggable("https://feeds.example.com/rss?token=abc&u=1#x") ==
               "https://feeds.example.com/rss"
    end

    test "keeps IPv6 brackets and port while dropping the query" do
      assert SafeHttp.loggable("http://[2001:db8::1]:8080/rss?token=x") ==
               "http://[2001:db8::1]:8080/rss"
    end

    test "hides a URL without a host, whose credentials URI.parse leaves in place" do
      assert SafeHttp.loggable("alice:pw@host/rss") == "<url without host>"
      assert SafeHttp.loggable("//alice:pw@host/x") == "//host/x"
      assert SafeHttp.loggable("https://alice:pw@:80/x") == "<url without host>"
      assert SafeHttp.loggable("https://alice:pw@/x") == "<url without host>"
      assert SafeHttp.loggable("https:alice:pw@host/x") == "<url without host>"
    end

    test "keeps a plain URL unchanged" do
      assert SafeHttp.loggable("https://feeds.example.com/rss") ==
               "https://feeds.example.com/rss"
    end
  end
end
