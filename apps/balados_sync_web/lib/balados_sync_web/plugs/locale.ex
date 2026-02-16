defmodule BaladosSyncWeb.Plugs.Locale do
  @moduledoc """
  Plug to set the locale for the current request.

  Works in two modes depending on whether a session is available:

  ## Browser mode (session available)

  Locale resolution order:
  1. `?locale=` query parameter (and persisted to session)
  2. Session `:locale`
  3. `Accept-Language` header
  4. Default locale ("fr")

  ## API mode (no session)

  Locale resolution order:
  1. `?locale=` query parameter
  2. `Accept-Language` header
  3. Default locale ("fr")

  API mode is automatically detected when the connection has no session
  (e.g., in the `:api` pipeline which does not call `:fetch_session`).
  """

  import Plug.Conn

  @supported_locales ["fr", "en"]

  defp default_locale do
    Application.get_env(:balados_sync_web, :default_locale, "fr")
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    has_session = session_available?(conn)

    locale =
      locale_from_params(conn) ||
        (has_session && locale_from_session(conn)) ||
        locale_from_header(conn) ||
        default_locale()

    Gettext.put_locale(BaladosSyncWeb.Gettext, locale)

    conn =
      if has_session && get_session(conn, :locale) != locale do
        put_session(conn, :locale, locale)
      else
        conn
      end

    assign(conn, :locale, locale)
  end

  defp session_available?(conn) do
    # The session is only available if :fetch_session was called upstream.
    # We check for the private key that Plug.Session sets after fetching.
    Map.has_key?(conn.private, :plug_session)
  end

  defp locale_from_params(conn) do
    conn.params["locale"] |> validate_locale()
  end

  defp locale_from_session(conn) do
    get_session(conn, :locale) |> validate_locale()
  end

  defp locale_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> parse_accept_language()
    |> validate_locale()
  end

  defp parse_accept_language([header | _]) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language_tag/1)
    |> Enum.sort_by(fn {_lang, q} -> q end, :desc)
    |> Enum.find_value(fn {lang, _q} -> validate_locale(lang) end)
  end

  defp parse_accept_language(_), do: nil

  defp parse_language_tag(tag) do
    case String.split(String.trim(tag), ";") do
      [lang, quality] ->
        q =
          case Regex.run(~r/q=([\d.]+)/, quality) do
            [_, value] -> String.to_float(value)
            _ -> 1.0
          end

        {normalize_lang(lang), q}

      [lang] ->
        {normalize_lang(lang), 1.0}
    end
  end

  defp normalize_lang(lang) do
    lang |> String.trim() |> String.downcase() |> String.split("-") |> List.first()
  end

  defp validate_locale(locale) when locale in @supported_locales, do: locale
  defp validate_locale(_), do: nil
end
