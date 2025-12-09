defmodule BaladosSyncWeb.PrivacyManagerController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.UserPrivacy
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.ChangePrivacy
  alias BaladosSyncCore.RssCache
  alias BaladosSyncWeb.Queries
  import Ecto.Query

  def index(conn, _params) do
    user_id = conn.assigns.current_user.id

    # Get all user subscriptions using Queries to get consistent formatting
    subscriptions = Queries.get_user_subscriptions(user_id)

    # Get privacy settings for each subscription
    privacy_map =
      ProjectionsRepo.all(
        from(p in UserPrivacy,
          where:
            p.user_id == ^user_id and
              p.rss_source_item == "",
          select: {p.rss_source_feed, p.privacy}
        )
      )
      |> Map.new()

    # Enrich subscriptions with privacy level and fetch metadata for titles and covers
    podcasts_with_privacy =
      Enum.map(subscriptions, fn sub ->
        privacy = Map.get(privacy_map, sub.rss_source_feed, "public")
        # Try to fetch metadata to get proper title and cover
        metadata = fetch_metadata_for_feed(sub.rss_source_feed)

        %{
          feed: sub.rss_source_feed,
          title: metadata.title || sub.rss_feed_title || "Untitled",
          cover: metadata.cover,
          privacy: privacy,
          privacy_atom: String.to_atom(privacy)
        }
      end)

    # Sort by title
    podcasts_with_privacy = Enum.sort_by(podcasts_with_privacy, & &1.title)

    # Log podcast covers status
    require Logger
    with_covers = Enum.count(podcasts_with_privacy, & &1.cover)
    total = Enum.count(podcasts_with_privacy)
    Logger.info("[PrivacyManager] Podcasts with covers: #{with_covers}/#{total}")

    Logger.info(
      "[PrivacyManager] First 3 podcasts: #{inspect(Enum.take(podcasts_with_privacy, 3))}"
    )

    # Group by privacy level
    grouped =
      Enum.group_by(podcasts_with_privacy, & &1.privacy_atom)

    render(conn, :index, podcasts: podcasts_with_privacy, grouped: grouped)
  end

  # Fetch metadata (title, cover) for a feed
  defp fetch_metadata_for_feed(encoded_feed) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      # Log the metadata.cover for debugging
      require Logger
      Logger.info("[PrivacyManager] Metadata cover: #{inspect(metadata.cover)}")
      Logger.info("[PrivacyManager] Full metadata: #{inspect(metadata)}")

      # Extract cover URL from metadata.cover (which is a map with src key)
      cover_url =
        case metadata.cover do
          %{src: url} when is_binary(url) -> url
          url when is_binary(url) -> url
          _ -> nil
        end

      Logger.info("[PrivacyManager] Extracted cover_url: #{inspect(cover_url)}")

      %{
        title: metadata.title,
        cover: cover_url
      }
    else
      err ->
        require Logger
        Logger.error("[PrivacyManager] Metadata fetch failed: #{inspect(err)}")
        %{title: nil, cover: nil}
    end
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
        # Check if it's an AJAX request
        if is_ajax_request?(conn) do
          json(conn, %{status: "success", privacy: privacy_str})
        else
          conn
          |> put_flash(:info, "Privacy level updated successfully")
          |> redirect(to: ~p"/privacy-manager")
        end

      {:error, reason} ->
        # Check if it's an AJAX request
        if is_ajax_request?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{status: "error", error: inspect(reason)})
        else
          conn
          |> put_flash(:error, "Failed to update privacy: #{inspect(reason)}")
          |> redirect(to: ~p"/privacy-manager")
        end
    end
  end

  # Check if request is AJAX (from fetch API)
  defp is_ajax_request?(conn) do
    case Plug.Conn.get_req_header(conn, "x-requested-with") do
      ["XMLHttpRequest"] -> true
      _ -> false
    end
  end

  # Generate device_id from IP (consistent with other controllers)
  defp generate_device_id(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    "web-#{:erlang.phash2(ip)}"
  end
end
