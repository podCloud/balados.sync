defmodule BaladosSyncProjections.Schemas.UserLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "users"
  schema "user_likes" do
    field :user_id, :string
    field :rss_source_feed, :string
    # nil for podcast likes, set for episode likes
    field :rss_source_item, :string
    field :liked_at, :utc_datetime
    field :unliked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(user_like, attrs) do
    user_like
    |> cast(attrs, [
      :user_id,
      :rss_source_feed,
      :rss_source_item,
      :liked_at,
      :unliked_at
    ])
    |> validate_required([:user_id, :rss_source_feed, :liked_at])
  end
end
