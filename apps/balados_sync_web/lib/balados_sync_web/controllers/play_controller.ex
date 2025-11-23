defmodule BaladosSyncWeb.PlayController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{RecordPlay, UpdatePosition}
  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.PlayStatus
  import Ecto.Query

  def record(conn, %{
        "rss_source_feed" => feed,
        "rss_source_item" => item,
        "position" => position,
        "played" => played
      }) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    command = %RecordPlay{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      position: position,
      played: played,
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

  def update_position(conn, %{"item" => item, "position" => position}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    # Récupérer le feed depuis les projections
    play_status = Repo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)

    command = %UpdatePosition{
      user_id: user_id,
      rss_source_feed: play_status && play_status.rss_source_feed,
      rss_source_item: item,
      position: position,
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

  def index(conn, params) do
    user_id = conn.assigns.current_user_id

    query =
      from(ps in PlayStatus,
        where: ps.user_id == ^user_id
      )

    # Filtres optionnels
    query =
      if params["played"] do
        played = params["played"] == "true"
        from(ps in query, where: ps.played == ^played)
      else
        query
      end

    query =
      if params["feed"] do
        from(ps in query, where: ps.rss_source_feed == ^params["feed"])
      else
        query
      end

    # Tri par date de mise à jour
    query = from(ps in query, order_by: [desc: ps.updated_at])

    # Pagination
    limit = min(String.to_integer(params["limit"] || "50"), 100)
    offset = String.to_integer(params["offset"] || "0")

    play_statuses =
      query
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    json(conn, %{
      play_statuses: play_statuses,
      pagination: %{
        limit: limit,
        offset: offset,
        total: Repo.aggregate(query, :count)
      }
    })
  end
end
