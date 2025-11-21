defmodule BaladosSyncProjections.Schemas.PlaylistItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users.playlist_items" do
    field :playlist_id, :binary_id
    field :rss_source_feed, :string
    field :rss_source_item, :string
    field :item_title, :string
    field :feed_title, :string
    field :deleted_at, :utc_datetime

    belongs_to :playlist, BaladosSyncProjections.Schemas.Playlist, define_field: false

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :playlist_id,
      :rss_source_feed,
      :rss_source_item,
      :item_title,
      :feed_title,
      :deleted_at
    ])
    |> validate_required([:playlist_id, :rss_source_item])
  end
end
