defmodule BaladosSyncProjections.Schemas.CollectionSubscription do
  @moduledoc """
  Projection schema for collection-feed associations.

  Maps podcast feeds to collections. This is a join table allowing
  many-to-many relationships between collections and feeds.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BaladosSyncProjections.Schemas.{Collection, Subscription}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "users"

  schema "collection_subscriptions" do
    field :collection_id, :binary_id
    field :rss_source_feed, :string
    field :position, :integer, default: 0

    belongs_to :collection, Collection,
      define_field: false,
      foreign_key: :collection_id,
      references: :id,
      type: :binary_id

    has_one :subscription, Subscription,
      foreign_key: :rss_source_feed,
      references: :rss_source_feed

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:collection_id, :rss_source_feed, :position])
    |> validate_required([:collection_id, :rss_source_feed])
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
