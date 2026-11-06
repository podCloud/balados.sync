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

  test "sends the given headers" do
    stub(fn conn ->
      assert Plug.Conn.get_req_header(conn, "cache-control") == ["no-cache"]
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert {:ok, "ok"} =
             get("https://feeds.example.org/feed", headers: [{"cache-control", "no-cache"}])
  end
end
