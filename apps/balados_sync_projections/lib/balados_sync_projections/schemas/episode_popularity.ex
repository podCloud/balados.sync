defmodule BaladosSyncProjections.Schemas.EpisodePopularity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @schema_prefix "public"
  schema "episode_popularity" do
    field :rss_source_feed, :string
    field :rss_source_item, :string, primary_key: true
    field :episode_title, :string
    field :episode_author, :string
    field :episode_description, :string
    field :podcast_title, :string
    # {src, srcset}
    field :episode_cover, :map
    field :score, :integer, default: 0
    field :score_previous, :integer, default: 0
    field :plays, :integer, default: 0
    field :plays_previous, :integer, default: 0
    field :plays_people, {:array, :string}, default: []
    field :likes, :integer, default: 0
    field :likes_previous, :integer, default: 0
    field :likes_people, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(popularity, attrs) do
    popularity
    |> cast(attrs, [
      :rss_source_feed,
      :rss_source_item,
      :episode_title,
      :episode_author,
      :episode_description,
      :podcast_title,
      :episode_cover,
      :score,
      :score_previous,
      :plays,
      :plays_previous,
      :plays_people,
      :likes,
      :likes_previous,
      :likes_people
    ])
    |> validate_required([:rss_source_item])
  end
end
