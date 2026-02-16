defmodule BaladosSyncWeb.WebSubscriptionsController do
  @moduledoc """
  Web interface for managing podcast subscriptions.

  Provides HTML views for users to manage their subscriptions, view feed details,
  and import/export subscriptions to OPML format. This is separate from the JSON API
  controller to keep concerns separated.

  Note: The main subscriptions listing is handled by SubscriptionsLive.
  This controller handles non-live actions: new, create, export_opml, import_opml.

  All actions require authenticated users.
  """

  use BaladosSyncWeb, :controller

  require Logger

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncCore.RssCache
  alias BaladosSyncCore.RssParser
  alias BaladosSyncWeb.Opml

  # Maximum OPML file size: 10MB
  @max_opml_file_size 10 * 1024 * 1024

  # All actions require authenticated user
  plug :require_authenticated_user

  @doc """
  Redirect subscription detail URLs to consolidated public podcast page.

  When users visit /subscriptions/:feed, they are redirected to the public
  /podcasts/:feed page which serves as the single source of truth for
  podcast information and subscription management.
  """
  def redirect_to_public(conn, %{"feed" => encoded_feed}) do
    redirect(conn, to: ~p"/podcasts/#{encoded_feed}")
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
            |> put_flash(:info, gettext("subscriptions.subscribed") <> " #{metadata.title}")
            |> redirect(to: ~p"/subscriptions")

          {:error, :already_subscribed} ->
            conn
            |> put_flash(:warning, gettext("subscriptions.already_subscribed"))
            |> redirect(to: ~p"/subscriptions")

          {:error, reason} ->
            Logger.warning("Subscription failed for user #{user_id}: #{inspect(reason)}")

            conn
            |> put_flash(:error, gettext("subscriptions.subscribe_failed"))
            |> render(:new, changeset: nil, preview: metadata)
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, gettext("subscriptions.invalid_feed") <> ": #{reason}")
        |> render(:new, changeset: nil, preview: nil)
    end
  end

  @doc """
  Export subscriptions to OPML file format.

  ## Query Parameters

  - `format` - "extended" (default) or "standard"
    - extended: Full export with play statuses, playlists, collections
    - standard: OPML 2.0 compatible (subscriptions only)
  """
  def export_opml(conn, params) do
    user_id = conn.assigns.current_user.id
    user = conn.assigns.current_user

    format =
      case params["format"] do
        "standard" -> :standard
        _ -> :extended
      end

    # Fetch all user data and convert to OPML document
    document = Opml.fetch_user_data(user_id)
    opml_content = Opml.to_xml(document, user, format: format)

    filename =
      case format do
        :standard -> "balados-subscriptions.opml"
        :extended -> "balados-sync-export.opml"
      end

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, opml_content)
  end

  @doc """
  Show OPML import form.
  """
  def import_opml_form(conn, _params) do
    render(conn, :import_opml)
  end

  @doc """
  Import subscriptions from OPML file.
  """
  def import_opml(conn, %{"opml" => %Plug.Upload{path: path}}) do
    user_id = conn.assigns.current_user.id

    # Security: Validate file size before reading to prevent memory exhaustion
    with {:ok, %{size: size}} <- File.stat(path),
         :ok <- validate_file_size(size) do
      import_opml_file(conn, user_id, path)
    else
      {:error, :file_too_large} ->
        max_mb = div(@max_opml_file_size, 1024 * 1024)

        conn
        |> put_flash(:error, gettext("import_opml.file_too_large") <> " #{max_mb}MB")
        |> render(:import_opml)

      {:error, reason} ->
        Logger.warning("File stat failed during OPML import: #{inspect(reason)}")

        conn
        |> put_flash(:error, gettext("import_opml.read_error"))
        |> render(:import_opml)
    end
  end

  def import_opml(conn, _params) do
    conn
    |> put_flash(:error, gettext("import_opml.no_file_selected"))
    |> render(:import_opml)
  end

  defp validate_file_size(size) when size <= @max_opml_file_size, do: :ok
  defp validate_file_size(_size), do: {:error, :file_too_large}

  defp import_opml_file(conn, user_id, path) do
    case File.read(path) do
      {:ok, content} ->
        case Opml.from_xml(content) do
          {:ok, document} ->
            case Opml.import_user_data(user_id, document) do
              {:ok, stats} ->
                flash_message = format_import_stats(stats)

                conn
                |> put_flash(:info, flash_message)
                |> redirect(to: ~p"/subscriptions")

              {:error, reason} ->
                Logger.error("OPML import failed for user #{user_id}: #{inspect(reason)}")

                conn
                |> put_flash(:error, gettext("import_opml.import_failed"))
                |> render(:import_opml)
            end

          {:error, :xml_parse_failed} ->
            conn
            |> put_flash(:error, gettext("import_opml.parse_error"))
            |> render(:import_opml)

          {:error, reason} ->
            Logger.warning("OPML parsing failed: #{inspect(reason)}")

            conn
            |> put_flash(:error, gettext("import_opml.invalid_format"))
            |> render(:import_opml)
        end

      {:error, reason} ->
        Logger.warning("File read failed during OPML import: #{inspect(reason)}")

        conn
        |> put_flash(:error, gettext("import_opml.read_error"))
        |> render(:import_opml)
    end
  end

  defp format_import_stats(stats) do
    parts = []

    parts =
      if stats.subscriptions.imported > 0 or stats.subscriptions.merged > 0 do
        count = stats.subscriptions.imported + stats.subscriptions.merged
        parts ++ ["#{count} " <> gettext("import_opml.subscriptions_count")]
      else
        parts
      end

    parts =
      if stats.play_statuses.imported > 0 or stats.play_statuses.merged > 0 do
        count = stats.play_statuses.imported + stats.play_statuses.merged
        parts ++ ["#{count} " <> gettext("import_opml.play_statuses_count")]
      else
        parts
      end

    parts =
      if stats.playlists.imported > 0 or stats.playlists.merged > 0 do
        count = stats.playlists.imported + stats.playlists.merged
        parts ++ ["#{count} " <> gettext("import_opml.playlists_count")]
      else
        parts
      end

    parts =
      if stats.collections.imported > 0 or stats.collections.merged > 0 do
        count = stats.collections.imported + stats.collections.merged
        parts ++ ["#{count} " <> gettext("import_opml.collections_count")]
      else
        parts
      end

    if Enum.empty?(parts) do
      gettext("import_opml.no_new_data")
    else
      gettext("import_opml.success") <> Enum.join(parts, ", ")
    end
  end

  # ===== Private Helpers =====

  defp preview_feed(url) do
    with {:ok, xml} <- RssCache.fetch_feed(url),
         {:ok, metadata} <- RssParser.parse_feed(xml) do
      {:ok, metadata}
    else
      {:error, :fetch_failed} -> {:error, gettext("subscriptions.fetch_failed")}
      {:error, :parse_failed} -> {:error, gettext("subscriptions.invalid_format")}
      _ -> {:error, gettext("subscriptions.unknown_error")}
    end
  end

  defp generate_source_id(feed_url) do
    # Generate deterministic ID from feed URL
    :crypto.hash(:sha256, feed_url)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, gettext("auth.must_log_in"))
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end
end
