defmodule BaladosSyncWeb.PrivacyController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.ChangePrivacy
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserPrivacy
  alias BaladosSyncWeb.Plugs.JWTAuth
  alias BaladosSyncWeb.Plugs.RateLimiter
  import BaladosSyncWeb.ErrorHelpers
  import Ecto.Query

  # Scope requirements for privacy settings
  plug JWTAuth, [scopes: ["user.privacy.read"]] when action in [:show]
  plug JWTAuth, [scopes: ["user.privacy.write"]] when action in [:update]

  # Rate limits per user
  plug RateLimiter, [limit: 100, window_ms: 60_000, key: :user_id, namespace: "privacy_read"]
       when action in [:show]

  plug RateLimiter, [limit: 30, window_ms: 60_000, key: :user_id, namespace: "privacy_write"]
       when action in [:update]

  def update(conn, %{"privacy" => privacy} = params) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    # Privacy peut être globale, par feed, ou par item
    feed = params["feed"]
    item = params["item"]

    privacy_atom =
      case privacy do
        "public" -> :public
        "anonymous" -> :anonymous
        "private" -> :private
        _ -> :public
      end

    command = %ChangePrivacy{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      privacy: privacy_atom,
      event_infos: %{
        device_id: device_id,
        device_name: device_name
      }
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        handle_dispatch_error(conn, reason)
    end
  end

  def show(conn, params) do
    user_id = conn.assigns.current_user_id

    query = from(p in UserPrivacy, where: p.user_id == ^user_id)

    # Filtrer par feed/item si spécifié
    query =
      if params["feed"] do
        from(p in query, where: p.rss_source_feed == ^params["feed"])
      else
        query
      end

    query =
      if params["item"] do
        from(p in query, where: p.rss_source_item == ^params["item"])
      else
        query
      end

    privacy_settings = ProjectionsRepo.all(query)

    json(conn, %{privacy_settings: privacy_settings})
  end
end
