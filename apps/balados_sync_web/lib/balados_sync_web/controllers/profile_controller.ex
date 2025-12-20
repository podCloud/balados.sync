defmodule BaladosSyncWeb.ProfileController do
  use BaladosSyncWeb, :controller

  alias BaladosSyncProjections.Schemas.User
  alias BaladosSyncProjections.Schemas.PublicEvent
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncCore.RssCache

  import Ecto.Query

  @doc """
  Shows the profile settings edit page for the current user.
  """
  def edit(conn, _params) do
    user = conn.assigns.current_user
    changeset = User.profile_changeset(user, %{})
    render(conn, :edit, user: user, changeset: changeset)
  end

  @doc """
  Updates the current user's profile settings.
  """
  def update(conn, %{"user" => profile_params}) do
    user = conn.assigns.current_user

    changeset = User.profile_changeset(user, profile_params)

    case SystemRepo.update(changeset) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, "Profile updated successfully.")
        |> redirect(to: ~p"/settings/profile")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, user: user, changeset: changeset)
    end
  end

  @doc """
  Shows a user's public profile page.

  Returns 404 if:
  - User doesn't exist
  - User's public profile is disabled
  """
  def show(conn, %{"username" => username}) do
    case get_public_user(username) do
      {:ok, user} ->
        # Get user's public timeline
        timeline = get_user_timeline(user.id)
        render(conn, :show, user: user, timeline: timeline)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: BaladosSyncWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  defp get_public_user(username) do
    case SystemRepo.get_by(User, username: username) do
      nil ->
        {:error, :not_found}

      user ->
        if user.public_profile_enabled do
          {:ok, user}
        else
          {:error, :not_found}
        end
    end
  end

  defp get_user_timeline(user_id) do
    # Query public events for this user
    events =
      from(pe in PublicEvent,
        where: pe.user_id == ^user_id and pe.privacy == "public",
        order_by: [desc: pe.event_timestamp],
        limit: 20
      )
      |> ProjectionsRepo.all()

    # Get feed URLs for metadata enrichment
    feed_urls =
      events
      |> Enum.map(& &1.rss_source_feed)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    feed_metadata = build_feed_metadata_map(feed_urls)

    # Format events for display
    Enum.map(events, fn event ->
      metadata = Map.get(feed_metadata, event.rss_source_feed)

      %{
        type: String.to_atom(event.event_type),
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        timestamp: event.event_timestamp,
        feed_title: metadata && metadata["title"],
        feed_image: metadata && get_in(metadata, ["cover", "src"]),
        item_title: event.event_data && event.event_data["item_title"]
      }
    end)
  end

  defp build_feed_metadata_map(encoded_feeds) do
    Enum.reduce(encoded_feeds, %{}, fn encoded_feed, acc ->
      case Base.url_decode64(encoded_feed, padding: false) do
        {:ok, feed_url} ->
          case RssCache.get_feed_metadata(feed_url) do
            {:ok, metadata} -> Map.put(acc, encoded_feed, metadata)
            _ -> acc
          end

        :error ->
          acc
      end
    end)
  end
end
