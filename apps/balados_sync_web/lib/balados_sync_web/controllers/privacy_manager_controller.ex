defmodule BaladosSyncWeb.PrivacyManagerController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.Subscription
  alias BaladosSyncProjections.Schemas.UserPrivacy
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.ChangePrivacy
  import Ecto.Query

  def index(conn, _params) do
    user_id = conn.assigns.current_user.id

    # Get all user subscriptions
    subscriptions =
      ProjectionsRepo.all(
        from s in Subscription,
        where: s.user_id == ^user_id and is_nil(s.unsubscribed_at),
        order_by: [asc: :rss_feed_title]
      )

    # Get privacy settings for each subscription
    privacy_map =
      ProjectionsRepo.all(
        from p in UserPrivacy,
        where:
          p.user_id == ^user_id and
            p.rss_source_item == "",
        select: {p.rss_source_feed, p.privacy}
      )
      |> Map.new()

    # Enrich subscriptions with privacy level
    podcasts_with_privacy =
      Enum.map(subscriptions, fn sub ->
        privacy = Map.get(privacy_map, sub.rss_source_feed, "public")

        %{
          feed: sub.rss_source_feed,
          title: sub.rss_feed_title || "Untitled",
          privacy: privacy,
          privacy_atom: String.to_atom(privacy)
        }
      end)

    # Group by privacy level
    grouped =
      Enum.group_by(podcasts_with_privacy, & &1.privacy_atom)

    render(conn, :index, podcasts: podcasts_with_privacy, grouped: grouped)
  end

  def update_privacy(conn, %{"feed" => encoded_feed, "privacy" => privacy_str}) do
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
        conn
        |> put_flash(:info, "Privacy level updated successfully")
        |> redirect(to: ~p"/privacy-manager")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to update privacy: #{inspect(reason)}")
        |> redirect(to: ~p"/privacy-manager")
    end
  end

  # Generate device_id from IP (consistent with other controllers)
  defp generate_device_id(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    "web-#{:erlang.phash2(ip)}"
  end
end
