defmodule BaladosSyncWeb.EpisodeController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{SaveEpisode, ShareEpisode}
  alias BaladosSyncWeb.Plugs.JWTAuth

  # Scope requirements for episode operations
  # Save and share are write operations that affect play status
  plug JWTAuth, [scopes: ["user.plays.write"]] when action in [:save, :share]

  def save(conn, %{"item" => item}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    # Le feed peut être passé en paramètre ou récupéré des projections
    feed = conn.params["feed"]

    command = %SaveEpisode{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def share(conn, %{"item" => item}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    feed = conn.params["feed"]

    command = %ShareEpisode{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end
end
