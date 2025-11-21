defmodule BaladosSyncWeb.PrivacyController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.App
  alias BaladosSyncCore.Commands.ChangePrivacy
  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.UserPrivacy
  import Ecto.Query

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
      device_id: device_id,
      device_name: device_name,
      rss_source_feed: feed,
      rss_source_item: item,
      privacy: privacy_atom
    }

    case App.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
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

    privacy_settings = Repo.all(query)

    json(conn, %{privacy_settings: privacy_settings})
  end
end
