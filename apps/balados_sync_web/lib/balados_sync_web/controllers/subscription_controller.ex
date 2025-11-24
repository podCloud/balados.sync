defmodule BaladosSyncWeb.SubscriptionController do
  @moduledoc """
  Controller for managing podcast subscriptions.

  This controller handles subscribing, unsubscribing, and listing podcast subscriptions
  for authenticated users. All operations use CQRS commands dispatched through the
  Commanded dispatcher, ensuring events are properly recorded in the event store.

  ## Routes

  - `POST /api/v1/subscriptions` - Subscribe to a podcast
  - `DELETE /api/v1/subscriptions/:feed` - Unsubscribe from a podcast
  - `GET /api/v1/subscriptions` - List all active subscriptions

  ## Authentication

  All endpoints require JWT authentication. The JWT must contain:
  - `sub` (user_id)
  - `device_id`
  - `device_name`

  ## Data Encoding

  RSS feed URLs are base64-encoded as `rss_source_feed` for safe URL transmission.
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, Unsubscribe}
  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.Subscription
  import Ecto.Query

  @doc """
  Subscribes to a podcast feed.

  Dispatches a `Subscribe` command that creates a `UserSubscribed` event in the event store.
  The event is then projected to the subscriptions read model.

  ## Parameters

  - `rss_source_feed` - Base64-encoded RSS feed URL
  - `rss_source_id` - Unique identifier for the podcast

  ## Example Request

      POST /api/v1/subscriptions
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      Content-Type: application/json

      {
        "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        "rss_source_id": "podcast-123"
      }

  ## Example Response (Success)

      {
        "status": "success"
      }

  ## Example Response (Error)

      {
        "error": "invalid_command"
      }
  """
  def create(conn, %{"rss_source_feed" => feed, "rss_source_id" => source_id}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    command = %Subscribe{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_id: source_id,
      subscribed_at: DateTime.utc_now(),
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
  Unsubscribes from a podcast feed.

  Dispatches an `Unsubscribe` command that creates a `UserUnsubscribed` event.
  The subscription remains in the database but is marked as unsubscribed.

  ## Parameters

  - `feed` - Base64-encoded RSS feed URL (from URL path)

  ## Example Request

      DELETE /api/v1/subscriptions/aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response (Success)

      {
        "status": "success"
      }

  ## Example Response (Error)

      {
        "error": "invalid_command"
      }
  """
  def delete(conn, %{"feed" => feed}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    # Récupérer le source_id depuis les projections
    subscription = Repo.get_by(Subscription, user_id: user_id, rss_source_feed: feed)

    command = %Unsubscribe{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_id: subscription && subscription.rss_source_id,
      unsubscribed_at: DateTime.utc_now(),
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
  Lists all active subscriptions for the authenticated user.

  Returns subscriptions from the read model where the subscription is currently active
  (either never unsubscribed, or subscribed_at is more recent than unsubscribed_at).

  ## Example Request

      GET /api/v1/subscriptions
      Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...

  ## Example Response

      {
        "subscriptions": [
          {
            "id": 1,
            "user_id": "user-123",
            "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
            "rss_source_id": "podcast-123",
            "subscribed_at": "2024-01-15T10:30:00Z",
            "unsubscribed_at": null,
            "inserted_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T10:30:00Z"
          }
        ]
      }
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user_id

    subscriptions =
      from(s in Subscription,
        where: s.user_id == ^user_id,
        where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at
      )
      |> Repo.all()

    json(conn, %{subscriptions: subscriptions})
  end
end
