defmodule BaladosSyncWeb.LikeController do
  @moduledoc """
  Controller for managing podcast and episode likes.

  ## Routes

  - `POST /api/v1/likes` - Like a podcast or episode
  - `DELETE /api/v1/likes/:feed` - Unlike a podcast
  - `DELETE /api/v1/likes/:feed/:item` - Unlike an episode
  - `GET /api/v1/likes` - List all active likes for the user (paginated)

  ## Path Parameters

  The `:feed` and `:item` path parameters must be **URL-safe base64** encoded
  (RFC 4648 §5: `-` instead of `+`, `_` instead of `/`, no `=` padding).
  Standard base64 contains `/` which would break path routing.
  See `balados.app/src/utils/rssEncoding.ts` for the shared encoding functions.
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncCore.Dispatcher

  alias BaladosSyncCore.Commands.{
    LikePodcast,
    UnlikePodcast,
    LikeEpisode,
    UnlikeEpisode
  }

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserLike
  alias BaladosSyncWeb.Plugs.JWTAuth
  alias BaladosSyncWeb.Plugs.RateLimiter
  import BaladosSyncWeb.ErrorHelpers
  import Ecto.Query

  plug JWTAuth, [scopes: ["user.likes.read"]] when action in [:index]

  plug JWTAuth,
       [scopes: ["user.likes.write"]] when action in [:create, :delete_podcast, :delete_episode]

  plug RateLimiter,
       [limit: 100, window_ms: 60_000, key: :user_id, namespace: "likes_read"]
       when action in [:index]

  plug RateLimiter,
       [limit: 30, window_ms: 60_000, key: :user_id, namespace: "likes_write"]
       when action in [:create, :delete_podcast, :delete_episode]

  def create(conn, %{"rss_source_feed" => feed, "rss_source_item" => item})
      when is_binary(item) and item != "" do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    command = %LikeEpisode{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      liked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        handle_dispatch_error(conn, reason)
    end
  end

  def create(conn, %{"rss_source_feed" => feed}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    command = %LikePodcast{
      user_id: user_id,
      rss_source_feed: feed,
      liked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        handle_dispatch_error(conn, reason)
    end
  end

  def create(conn, _params) do
    bad_request(conn, "Missing required parameter: rss_source_feed")
  end

  def delete_podcast(conn, %{"feed" => feed}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    command = %UnlikePodcast{
      user_id: user_id,
      rss_source_feed: feed,
      unliked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        handle_dispatch_error(conn, reason)
    end
  end

  def delete_episode(conn, %{"feed" => feed, "item" => item}) do
    user_id = conn.assigns.current_user_id
    device_id = conn.assigns.device_id
    device_name = conn.assigns.device_name

    command = %UnlikeEpisode{
      user_id: user_id,
      rss_source_feed: feed,
      rss_source_item: item,
      unliked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: %{device_id: device_id, device_name: device_name}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        json(conn, %{status: "success"})

      {:error, reason} ->
        handle_dispatch_error(conn, reason)
    end
  end

  @max_likes 500

  def index(conn, params) do
    user_id = conn.assigns.current_user_id
    limit = min(parse_int(params["limit"], @max_likes), @max_likes)
    offset = parse_int(params["offset"], 0)

    likes =
      from(ul in UserLike,
        where: ul.user_id == ^user_id and is_nil(ul.unliked_at),
        order_by: [desc: ul.liked_at],
        limit: ^(limit + 1),
        offset: ^offset,
        select: %{
          rss_source_feed: ul.rss_source_feed,
          rss_source_item: ul.rss_source_item,
          liked_at: ul.liked_at
        }
      )
      |> ProjectionsRepo.all()

    has_more = length(likes) > limit

    json(conn, %{
      likes: Enum.take(likes, limit),
      has_more: has_more
    })
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n >= 0 -> n
      _ -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val) and val >= 0, do: val
  defp parse_int(_, default), do: default
end
