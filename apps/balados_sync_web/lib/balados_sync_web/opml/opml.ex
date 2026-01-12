defmodule BaladosSyncWeb.Opml do
  @moduledoc """
  Extended OPML format with Balados namespace for full data export/import.

  This module defines the data structures used for OPML import/export and provides
  the main API for converting between XML and internal structures.

  ## Namespace

      xmlns:balados="https://balados.sync/opml/1.0"

  ## Structure

  The extended OPML contains three main sections:
  - Subscriptions (with play statuses nested)
  - Playlists (including queues)
  - Collections

  ## Usage

      # Export
      data = Opml.fetch_user_data(user_id)
      xml = Opml.to_xml(data, user, format: :extended)

      # Import
      {:ok, data} = Opml.from_xml(xml_string)
      Opml.import_user_data(user_id, data)

  ## External Apps

  See docs/technical/OPML_FORMAT.md for the full specification that external
  apps should follow to generate compatible OPML files.
  """

  alias BaladosSyncWeb.Opml.{Builder, Parser, DataFetcher, DataImporter}

  @namespace_url "https://balados.sync/opml/1.0"
  @version "1.0"

  # ===== Data Structures =====

  defmodule Subscription do
    @moduledoc "Subscription data structure for OPML"
    defstruct [
      :feed_url,
      :title,
      :subscribed_at,
      :unsubscribed_at,
      :privacy,
      :source_id,
      play_statuses: []
    ]

    @type t :: %__MODULE__{
      feed_url: String.t(),
      title: String.t() | nil,
      subscribed_at: DateTime.t() | nil,
      unsubscribed_at: DateTime.t() | nil,
      privacy: String.t(),
      source_id: String.t() | nil,
      play_statuses: [PlayStatus.t()]
    }
  end

  defmodule PlayStatus do
    @moduledoc "Play status (episode progress) data structure"
    defstruct [
      :guid,
      :position,
      :played,
      :updated_at
    ]

    @type t :: %__MODULE__{
      guid: String.t(),
      position: integer(),
      played: boolean(),
      updated_at: DateTime.t() | nil
    }
  end

  defmodule Playlist do
    @moduledoc "Playlist data structure for OPML"
    defstruct [
      :id,
      :name,
      :description,
      :type,
      :is_public,
      :updated_at,
      items: []
    ]

    @type t :: %__MODULE__{
      id: String.t() | nil,
      name: String.t(),
      description: String.t() | nil,
      type: String.t(),
      is_public: boolean(),
      updated_at: DateTime.t() | nil,
      items: [PlaylistItem.t()]
    }
  end

  defmodule PlaylistItem do
    @moduledoc "Playlist item data structure"
    defstruct [
      :feed_url,
      :guid,
      :position,
      :item_title,
      :feed_title
    ]

    @type t :: %__MODULE__{
      feed_url: String.t(),
      guid: String.t(),
      position: integer(),
      item_title: String.t() | nil,
      feed_title: String.t() | nil
    }
  end

  defmodule Collection do
    @moduledoc "Collection data structure for OPML"
    defstruct [
      :id,
      :title,
      :description,
      :is_public,
      :color,
      :updated_at,
      feeds: []
    ]

    @type t :: %__MODULE__{
      id: String.t() | nil,
      title: String.t(),
      description: String.t() | nil,
      is_public: boolean(),
      color: String.t() | nil,
      updated_at: DateTime.t() | nil,
      feeds: [String.t()]
    }
  end

  defmodule Document do
    @moduledoc "Complete OPML document structure"
    defstruct [
      :title,
      :date_created,
      :version,
      subscriptions: [],
      playlists: [],
      collections: []
    ]

    @type t :: %__MODULE__{
      title: String.t() | nil,
      date_created: DateTime.t() | nil,
      version: String.t() | nil,
      subscriptions: [Subscription.t()],
      playlists: [Playlist.t()],
      collections: [Collection.t()]
    }
  end

  # ===== Public API =====

  @doc """
  Returns the Balados OPML namespace URL.
  """
  def namespace_url, do: @namespace_url

  @doc """
  Returns the current Balados OPML format version.
  """
  def version, do: @version

  @doc """
  Fetch all user data and convert to OPML Document structure.

  ## Options

  - `:include_metadata` - Fetch RSS metadata for titles (default: true)
  """
  def fetch_user_data(user_id, opts \\ []) do
    DataFetcher.fetch(user_id, opts)
  end

  @doc """
  Convert an OPML Document to XML string.

  ## Options

  - `:format` - `:extended` (default) or `:standard`
  """
  def to_xml(%Document{} = doc, user, opts \\ []) do
    Builder.build(doc, user, opts)
  end

  @doc """
  Parse an XML string into an OPML Document.

  Returns `{:ok, document}` or `{:error, reason}`.
  """
  def from_xml(xml_string) do
    Parser.parse(xml_string)
  end

  @doc """
  Import OPML data for a user with conflict resolution.

  Uses the same merge strategy as the Sync API:
  - Subscriptions: Last-Write-Wins based on dates
  - Play statuses: Merge based on updated_at
  - Playlists/Collections: Merge based on updated_at
  """
  def import_user_data(user_id, %Document{} = doc, opts \\ []) do
    DataImporter.import(user_id, doc, opts)
  end

  # ===== Helpers =====

  @doc """
  Generate a fallback GUID for episodes without one.

  Format: `balados:generated:{base64(feed_url + enclosure_url)}`
  """
  def generate_fallback_guid(feed_url, enclosure_url) do
    data = "#{feed_url}:#{enclosure_url}"
    "balados:generated:#{Base.url_encode64(data, padding: false)}"
  end

  @doc """
  Check if a GUID is a Balados-generated fallback.
  """
  def generated_guid?(guid) do
    String.starts_with?(guid || "", "balados:generated:")
  end

  @doc """
  Decode a Balados-generated GUID back to feed_url and enclosure_url.
  """
  def decode_generated_guid("balados:generated:" <> encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} ->
        case String.split(decoded, ":", parts: 2) do
          [feed_url, enclosure_url] -> {:ok, feed_url, enclosure_url}
          _ -> {:error, :invalid_format}
        end
      _ ->
        {:error, :decode_failed}
    end
  end

  def decode_generated_guid(_), do: {:error, :not_generated}
end
