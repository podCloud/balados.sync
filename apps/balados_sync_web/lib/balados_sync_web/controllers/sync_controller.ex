defmodule BaladosSyncWeb.SyncController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.SyncUserData

  def sync(conn, params) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    # params contient: subscriptions, play_statuses, playlists
    command = %SyncUserData{
      user_id: user_id,
      subscriptions: parse_subscriptions(params["subscriptions"] || []),
      play_statuses: parse_play_statuses(params["play_statuses"] || []),
      playlists: parse_playlists(params["playlists"] || []),
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command, consistency: :strong) do
      :ok ->
        # Récupérer l'état synchronisé depuis les projections
        synced_data = get_user_data(user_id)

        json(conn, %{
          status: "success",
          data: synced_data
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp parse_subscriptions(subs) do
    Enum.reduce(subs, %{}, fn sub, acc ->
      Map.put(acc, sub["rss_source_feed"], %{
        rss_source_id: sub["rss_source_id"],
        subscribed_at: parse_datetime(sub["subscribed_at"]),
        unsubscribed_at: parse_datetime(sub["unsubscribed_at"])
      })
    end)
  end

  defp parse_play_statuses(statuses) do
    Enum.reduce(statuses, %{}, fn status, acc ->
      Map.put(acc, status["rss_source_item"], %{
        rss_source_feed: status["rss_source_feed"],
        position: status["position"],
        played: status["played"],
        updated_at: parse_datetime(status["updated_at"])
      })
    end)
  end

  defp parse_playlists(playlists) do
    # TODO: implémenter selon votre structure
    %{}
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp get_user_data(user_id) do
    %{
      subscriptions: BaladosSyncWeb.Queries.get_user_subscriptions(user_id),
      play_statuses: BaladosSyncWeb.Queries.get_user_play_statuses(user_id),
      playlists: BaladosSyncWeb.Queries.get_user_playlists(user_id)
    }
  end
end
