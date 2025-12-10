defmodule BaladosSyncWeb.LiveWebSocketController do
  @moduledoc """
  Controller for WebSocket upgrade requests.

  Handles HTTP to WebSocket upgrade for the live gateway.
  """

  use BaladosSyncWeb, :controller
  require Logger

  @doc """
  Upgrades HTTP request to WebSocket.

  Called at GET /api/v1/live and GET /sync/api/v1/live routes.

  Timeout is set to 5 minutes (300_000 ms) to allow long-lived connections.
  Periodic ping/pong keep-alive is handled in the WebSocket handler.
  """
  def upgrade(conn, _params) do
    Logger.debug("WebSocket upgrade requested from #{inspect(conn.remote_ip)}")

    WebSockAdapter.upgrade(
      conn,
      BaladosSyncWeb.LiveWebSocket,
      %{},
      timeout: 300_000,
      compress: false,
      max_frame_size: 65_536
    )
  end
end
