defmodule BaladosSyncProjections.Schemas.PodcastPopularity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "site.podcast_popularity" do
    field :rss_source_feed, :string, primary_key: true
    field :feed_title, :string
    field :feed_author, :string
    field :feed_description, :string
    # {src, srcset}
    field :feed_cover, :map
    field :score, :integer, default: 0
    field :score_previous, :integer, default: 0
    field :plays, :integer, default: 0
    field :plays_previous, :integer, default: 0
    # Liste user_ids récents
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
      :feed_title,
      :feed_author,
      :feed_description,
      :feed_cover,
      :score,
      :score_previous,
      :plays,
      :plays_previous,
      :plays_people,
      :likes,
      :likes_previous,
      :likes_people
    ])
    |> validate_required([:rss_source_feed])
  end
end
