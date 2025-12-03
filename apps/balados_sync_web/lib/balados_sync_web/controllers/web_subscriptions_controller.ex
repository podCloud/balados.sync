defmodule BaladosSyncWeb.WebSubscriptionsController do
  @moduledoc """
  Web interface for managing podcast subscriptions.

  Provides HTML views for users to manage their subscriptions, view feed details,
  and export subscriptions to OPML format. This is separate from the JSON API
  controller to keep concerns separated.

  All actions require authenticated users.
  """

  use BaladosSyncWeb, :controller

  require Logger

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{Subscribe, Unsubscribe}
  alias BaladosSyncCore.RssCache
  alias BaladosSyncCore.RssParser
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.Subscription
  alias BaladosSyncWeb.Queries
  alias BaladosSyncWeb.PlayTokenHelper

  # All actions require authenticated user
  plug :require_authenticated_user

  @doc """
  List all subscriptions for the current user.

  Loads metadata for each subscription asynchronously (via AJAX).
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    subscriptions = Queries.get_user_subscriptions(user_id)

    # Enrich subscriptions with cached metadata if available
    enriched_subscriptions =
      Enum.map(subscriptions, fn sub ->
        metadata = fetch_metadata_safe(sub.rss_source_feed)
        Map.put(sub, :metadata, metadata)
      end)

    render(conn, :index, subscriptions: enriched_subscriptions)
  end

  @doc """
  Show details of a single subscription (feed and episodes).

  Fetches the feed from RSS cache and displays episodes list.
  Automatically creates "Balados Web" play token if needed for play gateway links.
  """
  def show(conn, %{"feed" => encoded_feed}) do
    user_id = conn.assigns.current_user.id

    # Verify user is subscribed to this feed
    subscription =
      ProjectionsRepo.get_by(Subscription,
        user_id: user_id,
        rss_source_feed: encoded_feed
      )

    unless subscription do
      conn
      |> put_flash(:error, "Subscription not found")
      |> redirect(to: ~p"/my-subscriptions")
      |> halt()
    end

    # Get or create "Balados Web" token for play gateway links
    play_token_result = PlayTokenHelper.get_or_create_balados_web_token(user_id)

    # Fetch and parse feed
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, xml} <- RssCache.fetch_feed(feed_url),
         {:ok, metadata} <- RssParser.parse_feed(xml),
         {:ok, episodes} <- RssParser.parse_episodes(xml),
         {:ok, play_token} <- play_token_result do
      render(conn, :show,
        subscription: subscription,
        metadata: metadata,
        episodes: episodes,
        encoded_feed: encoded_feed,
        play_token: play_token
      )
    else
      {:error, reason} when reason != :invalid_base64 and reason != :fetch_failed and reason != :parse_failed ->
        Logger.error("Failed to get play token: #{inspect(reason)}")
        conn
        |> put_flash(:error, "Failed to load feed")
        |> redirect(to: ~p"/my-subscriptions")

      _ ->
        conn
        |> put_flash(:error, "Failed to load feed")
        |> redirect(to: ~p"/my-subscriptions")
    end
  end

  @doc """
  Show form to add a new subscription.
  """
  def new(conn, _params) do
    render(conn, :new, changeset: nil, preview: nil)
  end

  @doc """
  Create a new subscription from form submission.

  Validates the feed URL and dispatches a Subscribe command.
  """
  def create(conn, %{"feed_url" => feed_url}) do
    user_id = conn.assigns.current_user.id

    # Preview the feed to validate and get metadata
    case preview_feed(feed_url) do
      {:ok, metadata} ->
        # Encode feed and generate source_id
        encoded_feed = Base.url_encode64(feed_url, padding: false)
        source_id = generate_source_id(feed_url)

        # Dispatch Subscribe command
        command = %Subscribe{
          user_id: user_id,
          rss_source_feed: encoded_feed,
          rss_source_id: source_id,
          subscribed_at: DateTime.utc_now(),
          event_infos: %{
            device_id: "web-#{:erlang.phash2(conn.remote_ip)}",
            device_name: "Web Browser"
          }
        }

        case Dispatcher.dispatch(command) do
          :ok ->
            conn
            |> put_flash(:info, "Successfully subscribed to #{metadata.title}")
            |> redirect(to: ~p"/my-subscriptions")

          {:error, :already_subscribed} ->
            conn
            |> put_flash(:warning, "Already subscribed to this podcast")
            |> redirect(to: ~p"/my-subscriptions")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to subscribe: #{inspect(reason)}")
            |> render(:new, changeset: nil, preview: metadata)
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "Invalid feed: #{reason}")
        |> render(:new, changeset: nil, preview: nil)
    end
  end

  @doc """
  Unsubscribe from a podcast.
  """
  def delete(conn, %{"feed" => encoded_feed}) do
    user_id = conn.assigns.current_user.id

    # Get subscription for source_id
    subscription =
      ProjectionsRepo.get_by(Subscription,
        user_id: user_id,
        rss_source_feed: encoded_feed
      )

    unless subscription do
      conn
      |> put_flash(:error, "Subscription not found")
      |> redirect(to: ~p"/my-subscriptions")
      |> halt()
    end

    command = %Unsubscribe{
      user_id: user_id,
      rss_source_feed: encoded_feed,
      rss_source_id: subscription.rss_source_id,
      unsubscribed_at: DateTime.utc_now(),
      event_infos: %{
        device_id: "web-#{:erlang.phash2(conn.remote_ip)}",
        device_name: "Web Browser"
      }
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        conn
        |> put_flash(:info, "Successfully unsubscribed")
        |> redirect(to: ~p"/my-subscriptions")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to unsubscribe: #{inspect(reason)}")
        |> redirect(to: ~p"/my-subscriptions")
    end
  end

  @doc """
  Export subscriptions to OPML file format.
  """
  def export_opml(conn, _params) do
    user_id = conn.assigns.current_user.id
    subscriptions = Queries.get_user_subscriptions(user_id)

    # Enrich subscriptions with metadata for better OPML titles
    enriched_subscriptions =
      Enum.map(subscriptions, fn sub ->
        metadata = fetch_metadata_safe(sub.rss_source_feed)
        Map.put(sub, :metadata, metadata)
      end)

    opml_content = generate_opml(enriched_subscriptions, conn.assigns.current_user)

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="balados-subscriptions.opml")
    )
    |> send_resp(200, opml_content)
  end

  # ===== Private Helpers =====

  defp fetch_metadata_safe(encoded_feed) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      metadata
    else
      _ -> nil
    end
  end

  defp preview_feed(url) do
    with {:ok, xml} <- RssCache.fetch_feed(url),
         {:ok, metadata} <- RssParser.parse_feed(xml) do
      {:ok, metadata}
    else
      {:error, :fetch_failed} -> {:error, "Could not fetch feed"}
      {:error, :parse_failed} -> {:error, "Invalid RSS/XML format"}
      _ -> {:error, "Unknown error"}
    end
  end

  defp generate_source_id(feed_url) do
    # Generate deterministic ID from feed URL
    :crypto.hash(:sha256, feed_url)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp generate_opml(subscriptions, user) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    outlines =
      subscriptions
      |> Enum.map(fn sub ->
        with {:ok, feed_url} <- Base.url_decode64(sub.rss_source_feed, padding: false) do
          # Try to use metadata title first, then rss_feed_title, then default
          title =
            (sub.metadata && sub.metadata.title) ||
            sub.rss_feed_title ||
            "Unknown Podcast"

          ~s(<outline type="rss" text="#{escape_xml(title)}" xmlUrl="#{escape_xml(feed_url)}" />)
        else
          _ -> ""
        end
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n    ")

    username = user.username || "User"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>#{escape_xml(username)} - Balados Sync Subscriptions</title>
        <dateCreated>#{now}</dateCreated>
      </head>
      <body>
        #{outlines}
      </body>
    </opml>
    """
  end

  defp escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(_), do: ""

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access subscriptions")
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end
end
