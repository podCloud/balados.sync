defmodule BaladosSyncWeb.PlayController do
  require Logger

  @moduledoc """
  Controller for managing episode play status and playback position.

  This controller handles recording play events and updating playback positions for
  podcast episodes. All operations use CQRS commands to ensure proper event sourcing.

  ## Routes

  - `POST /api/v1/plays` - Record a play event with position and played status
  - `PATCH /api/v1/plays/:item` - Update playback position for an episode
  - `GET /api/v1/plays` - List play statuses with filtering and pagination

  ## Authentication

  All endpoints require JWT authentication.

  ## Data Encoding

  Episode identifiers (`rss_source_item`) are base64-encoded strings in the format:
  `"\#{guid},\#{enclosure_url}"` where guid and enclosure_url are from the RSS feed.
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{RecordPlay, UpdatePosition}
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.PlayStatus
  alias BaladosSyncWeb.Plugs.JWTAuth
  import Ecto.Query

  # Scope requirements for play status management
  plug JWTAuth, [scopes: ["user.plays.read"]] when action in [:index]
  plug JWTAuth, [scopes: ["user.plays.write"]] when action in [:record, :update_position]

  @doc """
  Records a play event for an episode.

  Dispatches a `RecordPlay` command that creates a `PlayRecorded` event. This updates
  both the playback position and the played (completed) status.

  ## Parameters

  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_item` - Base64-encoded episode identifier
  - `position` - Current playback position in seconds (integer)
  - `played` - Whether the episode has been completed (boolean)

  ## Example Request

      POST /api/v1/plays
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      Content-Type: application/json

      {
        "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        "rss_source_item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
        "position": 1234,
        "played": false
      }

  ## Example Response

      {
        "status": "success"
      }
  """
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

  @doc """
  Updates only the playback position for an episode.

  Dispatches an `UpdatePosition` command that creates a `PositionUpdated` event.
  This is useful for periodic position saves without marking the episode as played.

  ## Parameters

  - `item` - Base64-encoded episode identifier (from URL path)
  - `position` - Current playback position in seconds (integer)

  ## Example Request

      PATCH /api/v1/plays/Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      Content-Type: application/json

      {
        "position": 1567
      }

  ## Example Response

      {
        "status": "success"
      }
  """
  def update_position(conn, %{"item" => item, "position" => position}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    # Récupérer le feed depuis les projections
    play_status = ProjectionsRepo.get_by(PlayStatus, user_id: user_id, rss_source_item: item)

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

  @doc """
  Lists play statuses for the authenticated user.

  Returns play statuses from the read model with optional filtering and pagination.

  ## Query Parameters

  - `played` - Filter by played status: "true" or "false" (optional)
  - `feed` - Filter by base64-encoded feed URL (optional)
  - `limit` - Number of results per page (default: 50, max: 100)
  - `offset` - Number of results to skip (default: 0)

  ## Example Request

      GET /api/v1/plays?played=false&limit=20&offset=0
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response

      {
        "play_statuses": [
          {
            "id": 1,
            "user_id": "user-123",
            "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
            "rss_source_item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
            "position": 1234,
            "played": false,
            "updated_at": "2024-01-15T10:30:00Z"
          }
        ],
        "pagination": {
          "limit": 20,
          "offset": 0,
          "total": 45
        }
      }
  """
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
      |> ProjectionsRepo.all()

    json(conn, %{
      play_statuses: play_statuses,
      pagination: %{
        limit: limit,
        offset: offset,
        total: ProjectionsRepo.aggregate(query, :count)
      }
    })
  end
end
