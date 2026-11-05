defmodule BaladosSyncWeb.Plugs.CORS do
  @moduledoc """
  Minimal CORS handling for the JSON/RSS API (`/api/*`).

  balados.app is a PWA served from another origin and sends
  `Authorization: Bearer …` to the API, which makes the browser issue an
  `OPTIONS` preflight. Without this plug the preflight gets a 404 and the app
  never sees the real status codes (401/403/429), so its error handling cannot
  run.

  The API uses bearer tokens, never cookies, so `*` is a safe allowed origin
  (no credentials are involved). Headers are added through
  `register_before_send` so they are present on responses halted by plugs
  (auth, rate limiting), on controller responses and on router 404s. Errors
  raised *before* this plug (malformed JSON body in `Plug.Parsers`, request
  too large) are rendered from the pre-pipeline conn and carry no CORS
  headers; see the follow-up issue referenced in the PR.

  Mounted in the endpoint before the router so preflights are answered even
  for paths the router does not know.
  """

  @behaviour Plug

  import Plug.Conn

  @allowed_methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  @allowed_headers "Authorization, Content-Type, Accept, X-Requested-With"
  @exposed_headers "Retry-After, X-Request-Id"
  @max_age "86400"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: ["api" | _]} = conn, _opts) do
    if conn.method == "OPTIONS" do
      conn
      |> put_cors_headers()
      |> put_resp_header("access-control-allow-methods", @allowed_methods)
      |> put_resp_header("access-control-allow-headers", @allowed_headers)
      |> put_resp_header("access-control-max-age", @max_age)
      |> send_resp(204, "")
      |> halt()
    else
      register_before_send(conn, &put_cors_headers/1)
    end
  end

  def call(conn, _opts), do: conn

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-expose-headers", @exposed_headers)
  end
end
