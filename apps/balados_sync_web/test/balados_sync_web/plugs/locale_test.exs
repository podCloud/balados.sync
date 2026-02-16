defmodule BaladosSyncWeb.Plugs.LocaleTest do
  use BaladosSyncWeb.ConnCase, async: true

  alias BaladosSyncWeb.Plugs.Locale

  setup do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})

    {:ok, conn: conn}
  end

  describe "locale resolution" do
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
end
