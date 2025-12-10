defmodule BaladosSyncProjections.Schemas.Collection do
  @moduledoc """
  Projection schema for user collections.

  Collections allow users to organize their podcast subscriptions.
  Each user has one default collection (is_default: true) that automatically includes new subscriptions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BaladosSyncProjections.Schemas.CollectionSubscription

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "users"

  schema "collections" do
    field :user_id, :string
    field :title, :string
    field :is_default, :boolean, default: false
    field :description, :string
    field :color, :string
    field :deleted_at, :utc_datetime

    has_many :collection_subscriptions, CollectionSubscription,
      foreign_key: :collection_id,
      references: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:id, :user_id, :title, :is_default, :description, :color, :deleted_at, :inserted_at, :updated_at])
    |> validate_required([:user_id, :title, :is_default])
  end
end
