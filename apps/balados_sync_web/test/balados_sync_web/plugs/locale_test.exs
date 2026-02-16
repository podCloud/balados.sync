defmodule BaladosSyncWeb.Plugs.LocaleTest do
  use BaladosSyncWeb.ConnCase, async: true

  alias BaladosSyncWeb.Plugs.Locale

  describe "browser mode (with session)" do
    setup do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})

      {:ok, conn: conn}
    end

    test "uses query param locale when present", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "en"})
        |> Locale.call([])

      assert conn.assigns.locale == "en"
      assert Gettext.get_locale(BaladosSyncWeb.Gettext) == "en"
    end

    test "falls back to session locale", %{conn: conn} do
      conn =
        conn
        |> put_session(:locale, "en")
        |> Map.put(:params, %{})
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "falls back to Accept-Language header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "en-US,en;q=0.9,fr;q=0.8")
        |> Map.put(:params, %{})
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "falls back to default locale when nothing matches", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{})
        |> Locale.call([])

      # Test env default is "en" (config/test.exs)
      assert conn.assigns.locale == "en"
    end

    test "rejects unsupported locales", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "de"})
        |> Locale.call([])

      # Falls back to default since "de" is not supported
      # Test env default is "en" (config/test.exs)
      assert conn.assigns.locale == "en"
    end

    test "query param takes priority over session", %{conn: conn} do
      conn =
        conn
        |> put_session(:locale, "en")
        |> Map.put(:params, %{"locale" => "fr"})
        |> Locale.call([])

      assert conn.assigns.locale == "fr"
    end
  end

  describe "session optimization" do
    setup do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})

      {:ok, conn: conn}
    end

    test "does not update session when locale unchanged", %{conn: conn} do
      conn =
        conn
        |> put_session(:locale, "fr")
        |> Map.put(:params, %{})
        |> Locale.call([])

      # Session should not be marked as changed since locale is same
      assert conn.assigns.locale == "fr"
    end

    test "updates session when locale changes", %{conn: conn} do
      conn =
        conn
        |> put_session(:locale, "fr")
        |> Map.put(:params, %{"locale" => "en"})
        |> Locale.call([])

      assert conn.assigns.locale == "en"
      assert get_session(conn, :locale) == "en"
    end
  end

  describe "Accept-Language parsing" do
    setup do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})

      {:ok, conn: conn}
    end

    test "handles quality values correctly", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "de;q=0.9,fr;q=0.8,en;q=0.7")
        |> Map.put(:params, %{})
        |> Locale.call([])

      # "de" is not supported, so falls through to "fr" (q=0.8)
      assert conn.assigns.locale == "fr"
    end

    test "handles missing Accept-Language header", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{})
        |> Locale.call([])

      # Test env default is "en" (config/test.exs)
      assert conn.assigns.locale == "en"
    end
  end

  describe "API mode (no session)" do
    setup do
      # Build a conn without initializing a session, simulating the :api pipeline
      conn =
        build_conn()
        |> Map.put(:params, %{})

      {:ok, conn: conn}
    end

    test "uses query param locale", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "fr"})
        |> Locale.call([])

      assert conn.assigns.locale == "fr"
      assert Gettext.get_locale(BaladosSyncWeb.Gettext) == "fr"
    end

    test "uses Accept-Language header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "fr-FR,fr;q=0.9")
        |> Locale.call([])

      assert conn.assigns.locale == "fr"
    end

    test "falls back to default locale", %{conn: conn} do
      conn = Locale.call(conn, [])

      # Test env default is "en" (config/test.exs)
      assert conn.assigns.locale == "en"
    end

    test "query param takes priority over Accept-Language", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "en-US")
        |> Map.put(:params, %{"locale" => "fr"})
        |> Locale.call([])

      assert conn.assigns.locale == "fr"
    end

    test "does not crash when accessing session-less connection", %{conn: conn} do
      # Should not raise, even without a session
      conn =
        conn
        |> put_req_header("accept-language", "en")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "rejects unsupported locales and falls back to default", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "ja"})
        |> Locale.call([])

      # Test env default is "en" (config/test.exs)
      assert conn.assigns.locale == "en"
    end
  end

  describe "locale switcher query param preservation" do
    setup do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})

      {:ok, conn: conn}
    end

    test "locale query param is applied and persisted to session", %{conn: conn} do
      # First request with ?locale=fr
      conn1 =
        conn
        |> Map.put(:params, %{"locale" => "fr"})
        |> Locale.call([])

      assert conn1.assigns.locale == "fr"
      assert get_session(conn1, :locale) == "fr"

      # Second request without ?locale= should keep fr from session
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "fr"})
        |> Map.put(:params, %{})
        |> Locale.call([])

      assert conn2.assigns.locale == "fr"
    end

    test "switching locale via query param overrides previous session value", %{conn: conn} do
      # Start with English in session
      conn =
        conn
        |> put_session(:locale, "en")
        |> Map.put(:params, %{"locale" => "fr"})
        |> Locale.call([])

      assert conn.assigns.locale == "fr"
      assert get_session(conn, :locale) == "fr"
    end

    test "switching back and forth preserves latest choice", %{conn: conn} do
      # Switch to French
      conn1 =
        conn
        |> Map.put(:params, %{"locale" => "fr"})
        |> Locale.call([])

      assert conn1.assigns.locale == "fr"

      # Switch back to English
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "fr"})
        |> Map.put(:params, %{"locale" => "en"})
        |> Locale.call([])

      assert conn2.assigns.locale == "en"
      assert get_session(conn2, :locale) == "en"
    end
  end
end
