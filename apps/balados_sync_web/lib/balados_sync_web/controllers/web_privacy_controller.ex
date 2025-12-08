defmodule BaladosSyncWeb.WebPrivacyController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.ChangePrivacy
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserPrivacy
  import Ecto.Query

  # Check if privacy is set for a feed (session auth)
  def check_privacy(conn, %{"feed" => encoded_feed}) do
    # Unauthenticated users don't have privacy set
    unless conn.assigns[:current_user] do
      json(conn, %{has_privacy: false})
    else
      user_id = conn.assigns.current_user.id

      # Query for feed-level privacy (rss_source_item = "")
      privacy =
        ProjectionsRepo.one(
          from p in UserPrivacy,
          where:
            p.user_id == ^user_id and
              p.rss_source_feed == ^encoded_feed and
              p.rss_source_item == "",
          select: p.privacy
        )

      json(conn, %{
        has_privacy: privacy != nil,
        privacy: privacy
      })
    end
  end

  # Set privacy level for a feed (session auth)
  def set_privacy(conn, %{"feed" => encoded_feed, "privacy" => privacy_str}) do
    # Require authentication
    unless conn.assigns[:current_user] do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Authentication required"})
    else
      user_id = conn.assigns.current_user.id
      device_id = generate_device_id(conn)

      # Convert privacy string to atom
      privacy_atom =
        case privacy_str do
          "public" -> :public
          "anonymous" -> :anonymous
          "private" -> :private
          _ -> :public
        end

      # Dispatch ChangePrivacy command
      command = %ChangePrivacy{
        user_id: user_id,
        rss_source_feed: encoded_feed,
        rss_source_item: "",
        privacy: privacy_atom,
        event_infos: %{
          device_id: device_id,
          device_name: "Web Browser"
        }
      }

      case Dispatcher.dispatch(command) do
        :ok ->
          json(conn, %{status: "success", privacy: privacy_str})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: inspect(reason)})
      end
    end
  end

  # Generate device_id from IP (consistent with subscribe flow)
  defp generate_device_id(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    "web-#{:erlang.phash2(ip)}"
  end
end
