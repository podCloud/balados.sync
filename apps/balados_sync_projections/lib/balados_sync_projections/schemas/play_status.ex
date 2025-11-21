defmodule BaladosSyncProjections.Schemas.PlayStatus do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users.play_statuses" do
    field :user_id, :string
    field :rss_source_feed, :string
    field :rss_source_item, :string
    field :rss_feed_title, :string
    field :rss_item_title, :string
    field :played, :boolean, default: false
    field :position, :integer, default: 0
    # {duration, size, cover: {src, srcset}}
    field :rss_enclosure, :map

    field :updated_at, :utc_datetime
  end

  def changeset(play_status, attrs) do
    play_status
    |> cast(attrs, [
      :user_id,
      :rss_source_feed,
      :rss_source_item,
      :rss_feed_title,
      :rss_item_title,
      :played,
      :position,
      :rss_enclosure,
      :updated_at
    ])
    |> validate_required([:user_id, :rss_source_item])
  end
end
