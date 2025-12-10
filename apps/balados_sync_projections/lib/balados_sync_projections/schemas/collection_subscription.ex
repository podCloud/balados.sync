defmodule BaladosSyncProjections.Schemas.CollectionSubscription do
  @moduledoc """
  Projection schema for collection-feed associations.

  Maps podcast feeds to collections. This is a join table allowing
  many-to-many relationships between collections and feeds.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BaladosSyncProjections.Schemas.Collection

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "users"

  schema "collection_subscriptions" do
    field :collection_id, :binary_id
    field :rss_source_feed, :string

    belongs_to :collection, Collection,
      define_field: false,
      foreign_key: :collection_id,
      references: :id,
      type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:collection_id, :rss_source_feed])
    |> validate_required([:collection_id, :rss_source_feed])
  end
end
