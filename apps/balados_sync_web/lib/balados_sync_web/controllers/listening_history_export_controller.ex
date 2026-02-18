defmodule BaladosSyncWeb.ListeningHistoryExportController do
  @moduledoc """
  Handles CSV and JSON export for listening history data.
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.Queries

  plug :require_authenticated_user

  def export_csv(conn, params) do
    entries = get_filtered_entries(conn, params)

    csv_content = build_csv(entries)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="listening-history.csv"))
    |> send_resp(200, csv_content)
  end

  def export_json(conn, params) do
    entries = get_filtered_entries(conn, params)

    json_content =
      entries
      |> Enum.map(fn entry ->
        %{
          podcast: entry.rss_feed_title,
          episode: entry.rss_item_title,
          status: entry_status(entry),
          position: entry.position,
          date: entry.updated_at && DateTime.to_iso8601(entry.updated_at)
        }
      end)
      |> Jason.encode!(pretty: true)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="listening-history.json"))
    |> send_resp(200, json_content)
  end

  defp get_filtered_entries(conn, params) do
    user_id = conn.assigns.current_user.id

    opts =
      []
      |> maybe_add_opt(:feed, params["feed"])
      |> maybe_add_opt(:period, params["period"])
      |> maybe_add_opt(:status, params["status"])

    Queries.get_listening_history_export(user_id, opts)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, ""), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp build_csv(entries) do
    header = "Podcast,Episode,Status,Position (seconds),Date\r\n"

    rows =
      entries
      |> Enum.map(fn entry ->
        [
          csv_escape(entry.rss_feed_title || ""),
          csv_escape(entry.rss_item_title || ""),
          entry_status(entry),
          to_string(entry.position || 0),
          if(entry.updated_at, do: DateTime.to_iso8601(entry.updated_at), else: "")
        ]
        |> Enum.join(",")
      end)
      |> Enum.join("\r\n")

    header <> rows
  end

  defp csv_escape(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp entry_status(%{played: true}), do: "completed"
  defp entry_status(%{position: pos}) when pos > 0, do: "in_progress"
  defp entry_status(_), do: "not_started"

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
