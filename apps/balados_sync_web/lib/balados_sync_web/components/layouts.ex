defmodule BaladosSyncWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use BaladosSyncWeb, :controller` and
  `use BaladosSyncWeb, :live_view`.
  """
  use BaladosSyncWeb, :html

  @doc """
  Get WebSocket endpoint for JavaScript dispatch events

  Returns appropriate WebSocket URL based on environment:
  - Dev: ws://localhost:4000/sync/api/v1/live
  - Prod subdomain: wss://sync.example.com/api/v1/live
  - Prod path: wss://example.com/sync/api/v1/live
  """
  def get_ws_endpoint(conn) do
    scheme = if Mix.env() == :prod, do: "wss", else: "ws"

    # Check if using subdomain mode (config has play_domain set)
    play_domain = Application.get_env(:balados_sync_web, :play_domain)

    if play_domain && Mix.env() == :prod do
      # Subdomain mode: wss://sync.example.com/api/v1/live
      # Extract base domain from play_domain
      base_domain = String.replace(play_domain, ~r/^play\./, "")
      "#{scheme}://sync.#{base_domain}/api/v1/live"
    else
      # Path mode: wss://example.com/sync/api/v1/live
      host = conn.host || "localhost"
      port = get_dev_port()
      "#{scheme}://#{host}#{port}/sync/api/v1/live"
    end
  rescue
    # Fallback to path mode if anything fails
    _ ->
      host = conn.host || "localhost"
      port = get_dev_port()
      scheme = if Mix.env() == :prod, do: "wss", else: "ws"
      "#{scheme}://#{host}#{port}/sync/api/v1/live"
  end

  defp get_dev_port do
    if Mix.env() == :prod do
      ""
    else
      # Use config-based port instead of fragile conn.adapter inspection
      endpoint_config = Application.get_env(:balados_sync_web, BaladosSyncWeb.Endpoint) || []
      http_config = endpoint_config[:http] || []
      port = http_config[:port] || 4000
      ":#{port}"
    end
  end

  @doc """
  Get WebSocket authentication token for JavaScript

  Returns the "Balados Web Sync" PlayToken if user is authenticated, nil otherwise.
  This token is used for WebSocket play event tracking on subscription and discovery pages.
  """
  def get_ws_token(conn) do
    case conn.assigns[:current_user_id] do
      nil ->
        nil

      user_id ->
        # Try to get or create the "Balados Web Sync" play token for WebSocket
        try do
          case BaladosSyncWeb.PlayTokenHelper.get_or_create_websocket_token(user_id) do
            {:ok, token} -> token
            _ -> nil
          end
        rescue
          _ -> nil
        end
    end
  end

  embed_templates "layouts/*"
end
