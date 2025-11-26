defmodule BaladosSyncWeb.PlayGatewayController do
  use BaladosSyncWeb, :controller
  require Logger

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.RecordPlay
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.PlayToken
  import Ecto.Query

  def play(conn, %{"user_token" => token, "feed_id" => feed_id, "item_id" => item_id}) do
    with {:ok, user_id} <- verify_user_token(token),
         {:ok, feed_url} <- decode_base64(feed_id),
         {:ok, {guid, enclosure_url}} <- decode_item_id(item_id),
         :ok <- record_play_command(user_id, feed_url, "#{guid},#{enclosure_url}"),
         {:ok, final_enclosure_url} <- resolve_enclosure(enclosure_url) do
      # Mettre à jour last_used_at du token (async)
      update_token_last_used(token)

      # Redirection vers l'enclosure
      conn
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> redirect(external: final_enclosure_url)
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or revoked token"})

      {:error, :invalid_base64} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid ID encoding"})

      {:error, reason} ->
        Logger.error("Play gateway error: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  defp verify_user_token(token) do
    query =
      from(t in PlayToken,
        where: t.token == ^token and is_nil(t.revoked_at),
        select: t.user_id
      )

    case ProjectionsRepo.one(query) do
      nil -> {:error, :invalid_token}
      user_id -> {:ok, user_id}
    end
  end

  defp decode_base64(encoded) do
    case Base.decode64(encoded) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_item_id(encoded) do
    with {:ok, decoded} <- decode_base64(encoded) do
      case String.split(decoded, ",", parts: 2) do
        [guid, enclosure] -> {:ok, {guid, enclosure}}
        _ -> {:error, :invalid_format}
      end
    end
  end

  defp record_play_command(user_id, feed_url, item_id) do
    command = %RecordPlay{
      user_id: user_id,
      rss_source_feed: Base.encode64(feed_url),
      rss_source_item: Base.encode64(item_id),
      position: 0,
      played: false,
      event_infos: %{device_id: nil, device_name: "RSS Player"}
    }

    # Dispatch async pour ne pas bloquer la redirection
    Task.start(fn ->
      case Dispatcher.dispatch(command) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to record play: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp resolve_enclosure(url) do
    # Pour l'instant on retourne directement l'URL
    # On pourrait ajouter une résolution de redirections ici
    {:ok, url}
  end

  defp update_token_last_used(token) do
    Task.start(fn ->
      from(t in PlayToken, where: t.token == ^token)
      |> ProjectionsRepo.update_all(set: [last_used_at: DateTime.utc_now()])
    end)
  end
end
