defmodule BaladosSyncCore.RssParser do
  @moduledoc """
  Parses RSS/Atom podcast feeds and extracts metadata.

  Handles:
  - Feed-level metadata (title, description, author, cover)
  - Episode-level metadata (guid, title, description, duration, pub_date, enclosure)
  - iTunes podcast tags for enhanced metadata
  - Graceful error handling for malformed feeds
  """

  require Logger
  import SweetXml

  @doc """
  Parses RSS feed XML and extracts feed-level metadata.

  Returns {:ok, feed_metadata} or {:error, reason}

  ## Example
      iex> xml = File.read!("feed.xml")
      iex> {:ok, metadata} = RssParser.parse_feed(xml)
      iex> metadata.title
      "My Awesome Podcast"
  """
  def parse_feed(xml_string) when is_binary(xml_string) do
    doc = SweetXml.parse(xml_string)
    extract_feed_metadata(doc)
  rescue
    e ->
      Logger.error("RSS parsing error: #{inspect(e)}")
      {:error, :parse_failed}
  end

  @doc """
  Parses RSS feed XML and extracts episode-level metadata.

  Returns {:ok, [episodes]} or {:error, reason}

  ## Example
      iex> {:ok, episodes} = RssParser.parse_episodes(xml)
      iex> length(episodes)
      42
  """
  def parse_episodes(xml_string) when is_binary(xml_string) do
    doc = SweetXml.parse(xml_string)
    extract_episodes(doc)
  rescue
    e ->
      Logger.error("Episode parsing error: #{inspect(e)}")
      {:error, :parse_failed}
  end

  # ===== Feed Metadata Extraction =====

  defp extract_feed_metadata(doc) do
    try do
      title = extract_text(doc, ~x"//rss/channel/title/text()")
      description = extract_text(doc, ~x"//rss/channel/description/text()")
      author = extract_feed_author(doc)
      cover = extract_feed_cover(doc)
      language = extract_text(doc, ~x"//rss/channel/language/text()")
      episodes_count = count_items(doc)
      link = extract_text(doc, ~x"//rss/channel/link/text()")

      {:ok,
       %{
         title: title || "Unknown Podcast",
         description: description || "",
         author: author || "Unknown",
         cover: cover,
         language: language,
         episodes_count: episodes_count,
         link: link
       }}
    rescue
      _ -> {:error, :extraction_failed}
    end
  end

  defp extract_feed_author(doc) do
    # Try iTunes author first, then managingEditor
    case extract_text(doc, ~x"//rss/channel/itunes:author/text()") do
      nil -> extract_text(doc, ~x"//rss/channel/managingEditor/text()")
      author -> author
    end
  end

  defp extract_feed_cover(doc) do
    # Try iTunes image first, then RSS image
    src =
      case extract_text(doc, ~x"//rss/channel/itunes:image/@href") do
        nil -> extract_text(doc, ~x"//rss/channel/image/url/text()")
        url -> url
      end

    if src do
      %{src: src, srcset: nil}
    else
      nil
    end
  end

  defp count_items(doc) do
    doc
    |> SweetXml.xpath(~x"//rss/channel/item"l)
    |> length()
  end

  # ===== Episode Extraction =====

  defp extract_episodes(doc) do
    try do
      items =
        doc
        |> SweetXml.xpath(~x"//rss/channel/item"l)
        |> Enum.map(&extract_episode_metadata/1)
        |> Enum.reject(&is_nil/1)

      {:ok, items}
    rescue
      _ -> {:error, :episodes_extraction_failed}
    end
  end

  defp extract_episode_metadata(item) do
    try do
      guid = extract_text(item, ~x"./guid/text()")
      title = extract_text(item, ~x"./title/text()")

      if is_nil(guid) or is_nil(title) do
        nil
      else
        description = extract_text(item, ~x"./description/text()") || ""
        author = extract_episode_author(item)
        pub_date_raw = extract_text(item, ~x"./pubDate/text()") ||
                      extract_text(item, ~x"./published/text()") ||
                      extract_text(item, ~x"./updated/text()")
        pub_date = parse_pub_date(pub_date_raw)
        duration = parse_duration(extract_text(item, ~x"./itunes:duration/text()"))
        enclosure = extract_enclosure(item)
        cover = extract_text(item, ~x"./itunes:image/@href")
        link = extract_text(item, ~x"./link/text()")

        %{
          guid: guid,
          title: title,
          description: description,
          author: author,
          pub_date: pub_date,
          pub_date_raw: pub_date_raw,
          duration: duration,
          enclosure: enclosure,
          cover: cover,
          link: link
        }
      end
    rescue
      _ -> nil
    end
  end

  defp extract_episode_author(item) do
    case extract_text(item, ~x"./itunes:author/text()") do
      nil -> extract_text(item, ~x"./author/text()")
      author -> author
    end
  end

  defp extract_enclosure(item) do
    case extract_text(item, ~x"./enclosure/@url") do
      nil ->
        nil

      url ->
        type = extract_text(item, ~x"./enclosure/@type") || "audio/mpeg"
        length = extract_text(item, ~x"./enclosure/@length")

        length =
          if length && String.match?(length, ~r/^\d+$/) do
            String.to_integer(length)
          else
            0
          end

        %{
          url: url,
          type: type,
          length: length
        }
    end
  end

  # ===== Helper Functions =====

  defp extract_text(element, xpath) do
    case SweetXml.xpath(element, xpath) do
      nil -> nil
      "" -> nil
      text when is_binary(text) -> String.trim(text)
      text when is_list(text) -> text |> to_string() |> String.trim()
      _other -> nil
    end
  rescue
    _ -> nil
  end


  defp parse_pub_date(nil), do: nil

  defp parse_pub_date(date_string) when is_list(date_string) do
    parse_pub_date(to_string(date_string))
  end

  defp parse_pub_date(date_string) when is_binary(date_string) do
    date_string = String.trim(date_string)

    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _reason} ->
        # Try parsing RFC 2822 format manually: "Mon, 03 Jan 2022 06:00:00 +0000"
        parse_rfc2822_manual(date_string)
    end
  rescue
    _ ->
      nil
  end

  defp parse_rfc2822_manual(date_string) do
    # Format: "Day, DD Mon YYYY HH:MM:SS +/-HHMM"
    parts = String.split(date_string, " ", trim: true)

    case parts do
      [_day_comma, day, month_str, year, time_str, tz_str] ->
        try do
          # Parse components
          day_int = String.to_integer(day)
          year_int = String.to_integer(year)
          month_int = month_to_int(month_str)
          [h, m, s] = time_str |> String.split(":") |> Enum.map(&String.to_integer/1)

          # Parse timezone offset (e.g., "+0000" or "-0500")
          tz_offset = parse_tz_offset(tz_str)

          # Create NaiveDateTime then convert to DateTime
          {:ok, naive_dt} = NaiveDateTime.new(year_int, month_int, day_int, h, m, s, 0)
          {:ok, dt_utc} = DateTime.from_naive(naive_dt, "UTC")
          DateTime.add(dt_utc, -tz_offset, :second)
        rescue
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp month_to_int("Jan"), do: 1
  defp month_to_int("Feb"), do: 2
  defp month_to_int("Mar"), do: 3
  defp month_to_int("Apr"), do: 4
  defp month_to_int("May"), do: 5
  defp month_to_int("Jun"), do: 6
  defp month_to_int("Jul"), do: 7
  defp month_to_int("Aug"), do: 8
  defp month_to_int("Sep"), do: 9
  defp month_to_int("Oct"), do: 10
  defp month_to_int("Nov"), do: 11
  defp month_to_int("Dec"), do: 12
  defp month_to_int(_), do: raise(ArgumentError, "Invalid month")

  defp parse_tz_offset(tz_str) do
    case String.slice(tz_str, 0..0) do
      "+" ->
        offset_int = String.to_integer(String.slice(tz_str, 1..-1))
        hours = div(offset_int, 100)
        minutes = rem(offset_int, 100)
        hours * 3600 + minutes * 60

      "-" ->
        offset_int = String.to_integer(String.slice(tz_str, 1..-1))
        hours = div(offset_int, 100)
        minutes = rem(offset_int, 100)
        -(hours * 3600 + minutes * 60)

      _ ->
        0
    end
  rescue
    _ -> 0
  end

  defp parse_duration(nil), do: nil

  defp parse_duration(duration_string) when is_list(duration_string) do
    parse_duration(to_string(duration_string))
  end

  defp parse_duration(duration_string) when is_binary(duration_string) do
    duration_string = String.trim(duration_string)

    case Integer.parse(duration_string) do
      {seconds, ""} ->
        # Already in seconds
        seconds

      :error ->
        # Try HH:MM:SS format
        case String.split(duration_string, ":") do
          [hours, minutes, seconds] ->
            with {h, ""} <- Integer.parse(hours),
                 {m, ""} <- Integer.parse(minutes),
                 {s, ""} <- Integer.parse(seconds) do
              h * 3600 + m * 60 + s
            else
              _ -> nil
            end

          [minutes, seconds] ->
            with {m, ""} <- Integer.parse(minutes),
                 {s, ""} <- Integer.parse(seconds) do
              m * 60 + s
            else
              _ -> nil
            end

          _ ->
            nil
        end
    end
  rescue
    _ -> nil
  end
end
