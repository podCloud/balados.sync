defmodule BaladosSyncWeb.RssParser do
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
        pub_date = extract_and_parse_pub_date(item)
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

  # Extract pubDate from RSS or Atom feeds
  defp extract_and_parse_pub_date(item) do
    date_string =
      extract_text(item, ~x"./pubDate/text()") ||
      extract_text(item, ~x"./published/text()") ||
      extract_text(item, ~x"./updated/text()")

    parse_pub_date(date_string)
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

      :error ->
        # For RFC dates with timezone offset like "Mon, 03 Jan 2022 06:00:00 +0000"
        # Replace the offset with Z for Timex parsing
        clean_date = String.replace(date_string, ~r/ [+-]\d{4}$/, " Z")

        case Timex.parse(clean_date, "{RFC1123}") do
          {:ok, datetime} ->
            datetime

          :error ->
            nil
        end
    end
  rescue
    _ ->
      nil
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
