defmodule BaladosSyncProjections.Schemas.PublicEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "site"
  schema "public_events" do
    # null si anonymous
    field :user_id, :string
    field :event_type, :string
    field :rss_source_feed, :string
    field :rss_source_item, :string
    # public | anonymous
    field :privacy, :string
    field :event_data, :map
    field :event_timestamp, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :user_id,
      :event_type,
      :rss_source_feed,
      :rss_source_item,
      :privacy,
      :event_data,
      :event_timestamp
    ])
    |> validate_required([:event_type, :privacy, :event_timestamp])
  end
end
