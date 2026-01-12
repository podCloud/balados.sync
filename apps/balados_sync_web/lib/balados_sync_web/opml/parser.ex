defmodule BaladosSyncWeb.Opml.Parser do
  @moduledoc """
  Parses OPML XML into Document structure.

  Handles both standard OPML (subscriptions only) and extended OPML with
  Balados namespace (subscriptions + play statuses + playlists + collections).
  """

  alias BaladosSyncWeb.Opml.{Document, Subscription, PlayStatus, Playlist, PlaylistItem, Collection}

  @doc """
  Parse an XML string into an OPML Document.

  Returns `{:ok, document}` or `{:error, reason}`.
  """
  def parse(xml_string) when is_binary(xml_string) do
    case parse_xml(xml_string) do
      {:ok, parsed} ->
        document = extract_document(parsed)
        {:ok, document}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse(_), do: {:error, :invalid_input}

  # ===== XML Parsing =====

  defp parse_xml(xml_string) do
    try do
      # Use xmerl for parsing - it's included in Erlang/OTP
      # Security: Disable external entity loading to prevent XXE attacks
      {doc, _rest} = xml_string
        |> String.to_charlist()
        |> :xmerl_scan.string(
          quiet: true,
          fetch_fun: &block_external_entities/2
        )

      {:ok, doc}
    rescue
      _ -> {:error, :xml_parse_failed}
    catch
      :exit, _ -> {:error, :xml_parse_failed}
    end
  end

  # Security: Block all external entity requests to prevent XXE attacks
  defp block_external_entities(_uri, state) do
    # Return empty content and unchanged state - effectively disables external entities
    {:ok, {~c"", state}}
  end

  # ===== Document Extraction =====

  defp extract_document(xml_doc) do
    head = find_element(xml_doc, :head)
    body = find_element(xml_doc, :body)

    %Document{
      title: get_head_text(head, :title),
      date_created: get_head_date(head, :dateCreated),
      version: get_balados_version(head),
      subscriptions: extract_subscriptions(body),
      playlists: extract_playlists(body),
      collections: extract_collections(body)
    }
  end

  # ===== Head Parsing =====

  defp get_head_text(nil, _tag), do: nil
  defp get_head_text(head, tag) do
    case find_element(head, tag) do
      nil -> nil
      elem -> get_text_content(elem)
    end
  end

  defp get_head_date(head, tag) do
    case get_head_text(head, tag) do
      nil -> nil
      text -> parse_rfc822(text)
    end
  end

  defp get_balados_version(nil), do: nil
  defp get_balados_version(head) do
    # Look for balados:version element
    find_elements(head, :*) |> Enum.find_value(fn elem ->
      name = element_name(elem)
      if String.contains?(to_string(name), "version") do
        get_text_content(elem)
      end
    end)
  end

  # ===== Subscriptions Extraction =====

  defp extract_subscriptions(nil), do: []
  defp extract_subscriptions(body) do
    # Find all outline elements
    outlines = find_all_outlines(body)

    # Find "Subscriptions" section or top-level RSS outlines
    subscriptions_section = find_section(outlines, "Subscriptions")

    if subscriptions_section do
      # Extended format: outlines nested under Subscriptions section
      find_all_outlines(subscriptions_section)
      |> Enum.filter(&is_rss_outline?/1)
      |> Enum.map(&outline_to_subscription/1)
    else
      # Standard format: RSS outlines at any level
      outlines
      |> flatten_outlines()
      |> Enum.filter(&is_rss_outline?/1)
      |> Enum.map(&outline_to_subscription/1)
    end
  end

  defp is_rss_outline?(outline) do
    get_attr(outline, "type") == "rss" and get_attr(outline, "xmlUrl") != nil
  end

  defp outline_to_subscription(outline) do
    %Subscription{
      feed_url: get_attr(outline, "xmlUrl"),
      title: get_attr(outline, "text") || get_attr(outline, "title"),
      subscribed_at: get_balados_date_attr(outline, "subscribedAt"),
      unsubscribed_at: get_balados_date_attr(outline, "unsubscribedAt"),
      privacy: get_balados_attr(outline, "privacy") || "public",
      source_id: get_balados_attr(outline, "sourceId"),
      play_statuses: extract_play_statuses(outline)
    }
  end

  defp extract_play_statuses(outline) do
    find_all_outlines(outline)
    |> Enum.filter(fn o -> get_balados_attr(o, "type") == "playStatus" end)
    |> Enum.map(&outline_to_play_status/1)
  end

  defp outline_to_play_status(outline) do
    %PlayStatus{
      guid: get_balados_attr(outline, "guid"),
      position: get_balados_int_attr(outline, "position"),
      played: get_balados_bool_attr(outline, "played"),
      updated_at: get_balados_date_attr(outline, "updatedAt")
    }
  end

  # ===== Playlists Extraction =====

  defp extract_playlists(nil), do: []
  defp extract_playlists(body) do
    outlines = find_all_outlines(body)
    playlists_section = find_balados_section(outlines, "playlists")

    if playlists_section do
      find_all_outlines(playlists_section)
      |> Enum.filter(fn o -> get_balados_attr(o, "type") == "playlist" end)
      |> Enum.map(&outline_to_playlist/1)
    else
      []
    end
  end

  defp outline_to_playlist(outline) do
    %Playlist{
      id: get_balados_attr(outline, "id"),
      name: get_balados_attr(outline, "name"),
      description: get_balados_attr(outline, "description"),
      type: get_balados_attr(outline, "playlistType") || "playlist",
      is_public: get_balados_bool_attr(outline, "isPublic"),
      updated_at: get_balados_date_attr(outline, "updatedAt"),
      items: extract_playlist_items(outline)
    }
  end

  defp extract_playlist_items(outline) do
    find_all_outlines(outline)
    |> Enum.filter(fn o -> get_balados_attr(o, "type") == "playlistItem" end)
    |> Enum.map(&outline_to_playlist_item/1)
  end

  defp outline_to_playlist_item(outline) do
    %PlaylistItem{
      feed_url: get_balados_attr(outline, "feedUrl"),
      guid: get_balados_attr(outline, "guid"),
      position: get_balados_int_attr(outline, "position"),
      item_title: get_balados_attr(outline, "itemTitle"),
      feed_title: get_balados_attr(outline, "feedTitle")
    }
  end

  # ===== Collections Extraction =====

  defp extract_collections(nil), do: []
  defp extract_collections(body) do
    outlines = find_all_outlines(body)
    collections_section = find_balados_section(outlines, "collections")

    if collections_section do
      find_all_outlines(collections_section)
      |> Enum.filter(fn o -> get_balados_attr(o, "type") == "collection" end)
      |> Enum.map(&outline_to_collection/1)
    else
      []
    end
  end

  defp outline_to_collection(outline) do
    %Collection{
      id: get_balados_attr(outline, "id"),
      title: get_balados_attr(outline, "title"),
      description: get_balados_attr(outline, "description"),
      is_public: get_balados_bool_attr(outline, "isPublic"),
      color: get_balados_attr(outline, "color"),
      updated_at: get_balados_date_attr(outline, "updatedAt"),
      feeds: extract_collection_feeds(outline)
    }
  end

  defp extract_collection_feeds(outline) do
    find_all_outlines(outline)
    |> Enum.filter(fn o -> get_balados_attr(o, "type") == "collectionFeed" end)
    |> Enum.map(fn o -> get_balados_attr(o, "feedUrl") end)
    |> Enum.reject(&is_nil/1)
  end

  # ===== xmerl Helpers =====

  defp find_element(nil, _name), do: nil
  defp find_element({:xmlElement, _, _, _, _, _, _, _, content, _, _, _} = _elem, name) do
    content
    |> Enum.find(fn
      {:xmlElement, ^name, _, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
  end
  defp find_element(_, _), do: nil

  defp find_elements(nil, _name), do: []
  defp find_elements({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}, name) do
    Enum.filter(content, fn
      {:xmlElement, n, _, _, _, _, _, _, _, _, _, _} ->
        name == :* or n == name
      _ -> false
    end)
  end
  defp find_elements(_, _), do: []

  defp find_all_outlines(elem) do
    find_elements(elem, :outline)
  end

  defp flatten_outlines(outlines) do
    Enum.flat_map(outlines, fn outline ->
      children = find_all_outlines(outline)
      [outline | flatten_outlines(children)]
    end)
  end

  defp find_section(outlines, text) do
    Enum.find(outlines, fn outline ->
      get_attr(outline, "text") == text
    end)
  end

  defp find_balados_section(outlines, type) do
    Enum.find(outlines, fn outline ->
      get_balados_attr(outline, "type") == type or
        (get_attr(outline, "text") == String.capitalize(type))
    end)
  end

  defp element_name({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}), do: name
  defp element_name(_), do: nil

  defp get_text_content({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}) do
    content
    |> Enum.find_value(fn
      {:xmlText, _, _, _, text, _} -> to_string(text) |> String.trim()
      _ -> nil
    end)
  end
  defp get_text_content(_), do: nil

  defp get_attr({:xmlElement, _, _, _, _, _, _, attrs, _, _, _, _}, name) do
    attrs
    |> Enum.find_value(fn
      {:xmlAttribute, attr_name, _, _, _, _, _, _, value, _} ->
        if to_string(attr_name) == name, do: to_string(value)
      _ -> nil
    end)
  end
  defp get_attr(_, _), do: nil

  defp get_balados_attr(elem, name) do
    # Try both with and without namespace prefix
    get_attr(elem, "balados:#{name}") || get_attr(elem, name)
  end

  defp get_balados_int_attr(elem, name) do
    case get_balados_attr(elem, name) do
      nil -> nil
      str ->
        case Integer.parse(str) do
          {int, _} -> int
          :error -> nil
        end
    end
  end

  defp get_balados_bool_attr(elem, name) do
    case get_balados_attr(elem, name) do
      "true" -> true
      "false" -> false
      _ -> false
    end
  end

  defp get_balados_date_attr(elem, name) do
    case get_balados_attr(elem, name) do
      nil -> nil
      "" -> nil
      str -> parse_rfc822(str)
    end
  end

  # ===== Date Parsing =====

  defp parse_rfc822(nil), do: nil
  defp parse_rfc822(""), do: nil
  defp parse_rfc822(str) do
    # Try RFC 822 format first, then ISO 8601
    case parse_rfc822_strict(str) do
      {:ok, dt} -> dt
      _ ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _} -> dt
          _ -> nil
        end
    end
  end

  defp parse_rfc822_strict(str) do
    # RFC 822: "Sun, 12 Jan 2026 10:30:00 GMT"
    # Simplified parsing
    regex = ~r/(\w+), (\d+) (\w+) (\d+) (\d+):(\d+):(\d+)/

    case Regex.run(regex, str) do
      [_, _dow, day, month, year, hour, min, sec] ->
        month_num = month_to_number(month)
        if month_num do
          case NaiveDateTime.new(
            String.to_integer(year),
            month_num,
            String.to_integer(day),
            String.to_integer(hour),
            String.to_integer(min),
            String.to_integer(sec)
          ) do
            {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
            _ -> :error
          end
        else
          :error
        end
      _ -> :error
    end
  end

  defp month_to_number("Jan"), do: 1
  defp month_to_number("Feb"), do: 2
  defp month_to_number("Mar"), do: 3
  defp month_to_number("Apr"), do: 4
  defp month_to_number("May"), do: 5
  defp month_to_number("Jun"), do: 6
  defp month_to_number("Jul"), do: 7
  defp month_to_number("Aug"), do: 8
  defp month_to_number("Sep"), do: 9
  defp month_to_number("Oct"), do: 10
  defp month_to_number("Nov"), do: 11
  defp month_to_number("Dec"), do: 12
  defp month_to_number(_), do: nil
end
