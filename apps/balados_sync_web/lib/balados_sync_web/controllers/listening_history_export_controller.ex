defmodule BaladosSyncWeb.ListeningHistoryExportController do
  @moduledoc """
  Handles CSV and JSON export for listening history data.
  """

  use BaladosSyncWeb, :controller

  require Logger

  alias BaladosSyncWeb.Queries

  @max_export_rows Queries.max_export_rows()

  def export_csv(conn, params) do
    user = conn.assigns.current_user
    entries = get_filtered_entries(conn, params)
    entry_count = length(entries)

    Logger.info("Listening history export",
      format: "csv",
      user_id: user.id,
      entry_count: entry_count,
      filters: filter_params(params)
    )

    csv_content = build_csv(entries)

    conn
    |> maybe_add_truncation_header(entry_count)
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="listening-history.csv"))
    |> send_resp(200, csv_content)
  end

  def export_json(conn, params) do
    user = conn.assigns.current_user
    entries = get_filtered_entries(conn, params)
    entry_count = length(entries)

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

    Logger.info("Listening history export",
      format: "json",
      user_id: user.id,
      entry_count: entry_count,
      filters: filter_params(params)
    )

    conn
    |> maybe_add_truncation_header(entry_count)
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

  defp maybe_add_truncation_header(conn, entry_count) when entry_count >= @max_export_rows do
    put_resp_header(conn, "x-export-truncated", "true")
  end

  defp maybe_add_truncation_header(conn, _entry_count), do: conn

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

    header <> rows <> "\r\n"
  end

  defp csv_escape(value) do
    # Prefix formula-like values to prevent spreadsheet formula injection
    value =
      if String.starts_with?(value, ["=", "+", "-", "@"]) do
        "'" <> value
      else
        value
      end

    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp entry_status(%{played: true}), do: "completed"
  defp entry_status(%{position: pos}) when pos > 0, do: "in_progress"
  defp entry_status(_), do: "not_started"

  defp filter_params(params) do
    []
    |> maybe_add_opt(:feed, params["feed"])
    |> maybe_add_opt(:period, params["period"])
    |> maybe_add_opt(:status, params["status"])
    |> Enum.into(%{})
  end
end
