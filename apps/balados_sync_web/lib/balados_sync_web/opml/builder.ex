defmodule BaladosSyncWeb.Opml.Builder do
  @moduledoc """
  Builds XML from OPML Document structure.
  """

  alias BaladosSyncWeb.Opml
  alias BaladosSyncWeb.Opml.Document

  @doc """
  Build XML string from OPML Document.

  ## Options

  - `:format` - `:extended` (default) or `:standard`
  """
  def build(%Document{} = doc, user, opts \\ []) do
    format = Keyword.get(opts, :format, :extended)

    case format do
      :standard -> build_standard(doc, user)
      :extended -> build_extended(doc, user)
    end
  end

  # ===== Standard OPML =====

  defp build_standard(doc, user) do
    outlines =
      doc.subscriptions
      |> Enum.map(&subscription_to_standard_outline/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n    ")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>#{escape(user.username || "User")} - Balados Sync Subscriptions</title>
        <dateCreated>#{format_rfc822(DateTime.utc_now())}</dateCreated>
      </head>
      <body>
        #{outlines}
      </body>
    </opml>
    """
  end

  defp subscription_to_standard_outline(sub) do
    if sub.feed_url do
      ~s(<outline type="rss" text="#{escape(sub.title || "Unknown")}" xmlUrl="#{escape(sub.feed_url)}"/>)
    end
  end

  # ===== Extended OPML =====

  defp build_extended(doc, user) do
    subscriptions_section = build_subscriptions_section(doc.subscriptions)
    playlists_section = build_playlists_section(doc.playlists)
    collections_section = build_collections_section(doc.collections)
    version_tag = "<" <> "balados:version" <> ">#{Opml.version()}</" <> "balados:version" <> ">"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0" xmlns:balados="#{Opml.namespace_url()}">
      <head>
        <title>#{escape(user.username || "User")} - Balados Sync Export</title>
        <dateCreated>#{format_rfc822(DateTime.utc_now())}</dateCreated>
        #{version_tag}
      </head>
      <body>
    #{subscriptions_section}#{playlists_section}#{collections_section}
      </body>
    </opml>
    """
  end

  # ===== Subscriptions Section =====

  defp build_subscriptions_section([]), do: ""

  defp build_subscriptions_section(subscriptions) do
    outlines =
      subscriptions
      |> Enum.map(&subscription_to_extended_outline/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    """
        <outline text="Subscriptions">
    #{outlines}
        </outline>
    """
  end

  defp subscription_to_extended_outline(sub) do
    return_nil_if_no_url(sub.feed_url, fn ->
      attrs = build_subscription_attrs(sub)
      play_statuses = sub.play_statuses || []

      if Enum.empty?(play_statuses) do
        "      <outline #{attrs}/>"
      else
        ps_outlines =
          play_statuses
          |> Enum.map(&play_status_to_outline/1)
          |> Enum.join("\n")

        "      <outline #{attrs}>\n#{ps_outlines}\n      </outline>"
      end
    end)
  end

  defp build_subscription_attrs(sub) do
    [
      ~s(type="rss"),
      ~s(text="#{escape(sub.title || "Unknown")}"),
      ~s(xmlUrl="#{escape(sub.feed_url)}"),
      ~s(balados:subscribedAt="#{format_rfc822(sub.subscribed_at)}"),
      optional_attr("balados:unsubscribedAt", sub.unsubscribed_at, &format_rfc822/1),
      ~s(balados:privacy="#{sub.privacy || "public"}"),
      optional_attr("balados:sourceId", sub.source_id)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp play_status_to_outline(ps) do
    attrs =
      [
        ~s(balados:type="playStatus"),
        ~s(balados:guid="#{escape(ps.guid)}"),
        ~s(balados:position="#{ps.position || 0}"),
        ~s(balados:played="#{ps.played || false}"),
        ~s(balados:updatedAt="#{format_rfc822(ps.updated_at)}")
      ]
      |> Enum.join(" ")

    "        <outline #{attrs}/>"
  end

  # ===== Playlists Section =====

  defp build_playlists_section([]), do: ""

  defp build_playlists_section(playlists) do
    outlines =
      playlists
      |> Enum.map(&playlist_to_outline/1)
      |> Enum.join("\n")

    # Using concat to avoid heredoc parsing balados:type as Elixir keyword
    "    <outline text=\"Playlists\" " <>
      "balados:type" <>
      "=\"playlists\">\n" <>
      outlines <>
      "\n" <>
      "    </outline>\n"
  end

  defp playlist_to_outline(playlist) do
    attrs = build_playlist_attrs(playlist)
    items = playlist.items || []

    if Enum.empty?(items) do
      "      <outline #{attrs}/>"
    else
      item_outlines =
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} -> playlist_item_to_outline(item, idx) end)
        |> Enum.join("\n")

      "      <outline #{attrs}>\n#{item_outlines}\n      </outline>"
    end
  end

  defp build_playlist_attrs(playlist) do
    [
      ~s(balados:type="playlist"),
      optional_attr("balados:id", playlist.id),
      ~s(balados:name="#{escape(playlist.name || "")}"),
      optional_attr("balados:description", playlist.description),
      ~s(balados:playlistType="#{playlist.type || "playlist"}"),
      ~s(balados:isPublic="#{playlist.is_public || false}"),
      ~s(balados:updatedAt="#{format_rfc822(playlist.updated_at)}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp playlist_item_to_outline(item, position) do
    attrs =
      [
        ~s(balados:type="playlistItem"),
        ~s(balados:feedUrl="#{escape(item.feed_url || "")}"),
        ~s(balados:guid="#{escape(item.guid || "")}"),
        ~s(balados:position="#{item.position || position}"),
        optional_attr("balados:itemTitle", item.item_title),
        optional_attr("balados:feedTitle", item.feed_title)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    "        <outline #{attrs}/>"
  end

  # ===== Collections Section =====

  defp build_collections_section([]), do: ""

  defp build_collections_section(collections) do
    outlines =
      collections
      |> Enum.map(&collection_to_outline/1)
      |> Enum.join("\n")

    # Using concat to avoid heredoc parsing balados:type as Elixir keyword
    "    <outline text=\"Collections\" " <>
      "balados:type" <>
      "=\"collections\">\n" <>
      outlines <>
      "\n" <>
      "    </outline>\n"
  end

  defp collection_to_outline(collection) do
    attrs = build_collection_attrs(collection)
    feeds = collection.feeds || []

    if Enum.empty?(feeds) do
      "      <outline #{attrs}/>"
    else
      feed_outlines =
        feeds
        |> Enum.map(&collection_feed_to_outline/1)
        |> Enum.join("\n")

      "      <outline #{attrs}>\n#{feed_outlines}\n      </outline>"
    end
  end

  defp build_collection_attrs(collection) do
    [
      ~s(balados:type="collection"),
      optional_attr("balados:id", collection.id),
      ~s(balados:title="#{escape(collection.title || "")}"),
      optional_attr("balados:description", collection.description),
      ~s(balados:isPublic="#{collection.is_public || false}"),
      optional_attr("balados:color", collection.color),
      ~s(balados:updatedAt="#{format_rfc822(collection.updated_at)}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp collection_feed_to_outline(feed_url) do
    ~s(        <outline balados:type="collectionFeed" balados:feedUrl="#{escape(feed_url)}"/>)
  end

  # ===== Helpers =====

  defp return_nil_if_no_url(nil, _fun), do: nil
  defp return_nil_if_no_url("", _fun), do: nil
  defp return_nil_if_no_url(_url, fun), do: fun.()

  defp optional_attr(_name, nil), do: nil
  defp optional_attr(_name, ""), do: nil
  defp optional_attr(name, value), do: ~s(#{name}="#{escape(value)}")

  defp optional_attr(_name, nil, _formatter), do: nil

  defp optional_attr(name, value, formatter) do
    formatted = formatter.(value)
    if formatted == "" or is_nil(formatted), do: nil, else: ~s(#{name}="#{formatted}")
  end

  defp format_rfc822(nil), do: ""

  defp format_rfc822(%DateTime{} = dt) do
    Calendar.strftime(dt, "%a, %d %b %Y %H:%M:%S GMT")
  end

  defp format_rfc822(_), do: ""

  defp escape(nil), do: ""

  defp escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape(value), do: escape(to_string(value))
end
