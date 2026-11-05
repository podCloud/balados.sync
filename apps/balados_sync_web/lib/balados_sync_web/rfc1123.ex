defmodule BaladosSyncWeb.Rfc1123 do
  @moduledoc """
  RFC 1123 / RFC 2822 date handling for RSS (`<pubDate>`, `<lastBuildDate>`),
  without an external library.

  `format/1` produces the exact string Timex's `{RFC1123}` produced for UTC
  datetimes: `"Thu, 05 Nov 2026 18:00:00 +0000"`.
  """

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @month_numbers @months |> Enum.with_index(1) |> Map.new()

  # RFC 822 §5 zone names. GMT/UT/Z and the North American zones are the ones
  # still met in podcast feeds; other alphabetic zones are rejected (:error),
  # as are two-digit offsets such as "+00" (RFC 2822 requires four digits).
  @named_zones %{
    "GMT" => 0,
    "UTC" => 0,
    "UT" => 0,
    "Z" => 0,
    "EST" => -5 * 3600,
    "EDT" => -4 * 3600,
    "CST" => -6 * 3600,
    "CDT" => -5 * 3600,
    "MST" => -7 * 3600,
    "MDT" => -6 * 3600,
    "PST" => -8 * 3600,
    "PDT" => -7 * 3600
  }

  @doc "Formats a `DateTime` in UTC as `Ddd, DD Mon YYYY HH:MM:SS +0000`."
  @spec format(DateTime.t()) :: String.t()
  def format(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S +0000")
  end

  @doc """
  Parses `[Weekday, ]D[D] Mon YYYY HH:MM:SS (+|-)HHMM|GMT|UTC|EST|…` into a UTC
  `DateTime`. Returns `:error` for anything else.
  """
  @spec parse(term()) :: {:ok, DateTime.t()} | :error
  def parse(string) when is_binary(string) do
    parts = string |> String.trim() |> String.split(~r/\s+/)

    parts =
      case parts do
        [weekday | rest]
        when byte_size(weekday) > 1 and binary_part(weekday, byte_size(weekday) - 1, 1) == "," ->
          rest

        _ ->
          parts
      end

    with [day, month, year, time, zone] <- parts,
         {:ok, day} <- parse_digits(day, 1..2),
         {:ok, month} <- Map.fetch(@month_numbers, month),
         {:ok, year} <- parse_digits(year, 4..4),
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
        with {:ok, h} <- parse_digits(h, 1..2),
             {:ok, m} <- parse_digits(m, 2..2),
             {:ok, s} <- parse_digits(s, 2..2) do
          {:ok, {h, m, s}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_offset(<<sign, hhmm::binary-size(4)>>) when sign in [?+, ?-] do
    with {:ok, hours} <- parse_digits(binary_part(hhmm, 0, 2), 2..2),
         {:ok, minutes} when minutes < 60 <- parse_digits(binary_part(hhmm, 2, 2), 2..2) do
      seconds = hours * 3600 + minutes * 60
      {:ok, if(sign == ?-, do: -seconds, else: seconds)}
    else
      _ -> :error
    end
  end

  defp parse_offset(zone), do: Map.fetch(@named_zones, zone)

  # Unsigned decimal digits only: Integer.parse/1 would accept "+3" or "-2025".
  defp parse_digits(string, min..max//_) do
    len = byte_size(string)

    if len >= min and len <= max and string =~ ~r/^[0-9]+$/ do
      {:ok, String.to_integer(string)}
    else
      :error
    end
  end
end
