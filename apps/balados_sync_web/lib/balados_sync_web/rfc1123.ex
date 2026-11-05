defmodule BaladosSyncWeb.Rfc1123 do
  @moduledoc """
  RFC 1123 / RFC 2822 date handling for RSS (`<pubDate>`, `<lastBuildDate>`),
  without an external library.

  `format/1` produces the exact string Timex's `{RFC1123}` produced for UTC
  datetimes: `"Thu, 05 Nov 2026 18:00:00 +0000"`.
  """

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @month_numbers @months |> Enum.with_index(1) |> Map.new()

  @zero_offset_zones ~w(GMT UTC UT Z)

  @doc "Formats a `DateTime` in UTC as `Ddd, DD Mon YYYY HH:MM:SS +0000`."
  @spec format(DateTime.t()) :: String.t()
  def format(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S +0000")
  end

  @doc """
  Parses `[Ddd, ]D[D] Mon YYYY HH:MM:SS (+|-)HHMM|GMT|UTC|Z` into a UTC
  `DateTime`. Returns `:error` for anything else.
  """
  @spec parse(String.t() | nil) :: {:ok, DateTime.t()} | :error
  def parse(nil), do: :error

  def parse(string) when is_binary(string) do
    parts = string |> String.trim() |> String.split(~r/\s+/)

    parts =
      case parts do
        [weekday | rest] when byte_size(weekday) == 4 -> rest
        _ -> parts
      end

    with [day, month, year, time, zone] <- parts,
         {day, ""} <- Integer.parse(day),
         {:ok, month} <- Map.fetch(@month_numbers, month),
         {year, ""} <- Integer.parse(year),
         {:ok, {hour, minute, second}} <- parse_time(time),
         {:ok, offset} <- parse_offset(zone),
         {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, second),
         {:ok, utc} <- DateTime.from_naive(naive, "Etc/UTC") do
      {:ok, DateTime.add(utc, -offset, :second)}
    else
      _ -> :error
    end
  end

  def parse(_), do: :error

  defp parse_time(time) do
    case String.split(time, ":") do
      [h, m, s] ->
        with {h, ""} <- Integer.parse(h),
             {m, ""} <- Integer.parse(m),
             {s, ""} <- Integer.parse(s) do
          {:ok, {h, m, s}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_offset(zone) when zone in @zero_offset_zones, do: {:ok, 0}

  defp parse_offset(<<sign, hh::binary-size(2), mm::binary-size(2)>>) when sign in [?+, ?-] do
    with {hours, ""} <- Integer.parse(hh),
         {minutes, ""} <- Integer.parse(mm) do
      seconds = hours * 3600 + minutes * 60
      {:ok, if(sign == ?-, do: -seconds, else: seconds)}
    else
      _ -> :error
    end
  end

  defp parse_offset(_), do: :error
end
