defmodule BaladosSyncWeb.SubscriptionController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, Unsubscribe}
  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.Subscription
  import Ecto.Query

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
