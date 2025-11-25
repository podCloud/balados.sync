defmodule BaladosSyncProjections.Repo.Migrations.CreatePodcastPopularity do
  use Ecto.Migration

  def change do
    create table(:podcast_popularity, primary_key: false, prefix: "site") do
      add :rss_source_feed, :text, primary_key: true
      add :feed_title, :text
      add :feed_author, :text
      add :feed_description, :text
      add :feed_cover, :jsonb
      add :score, :integer, default: 0, null: false
      add :score_previous, :integer, default: 0, null: false
      add :plays, :integer, default: 0, null: false
      add :plays_previous, :integer, default: 0, null: false
      add :plays_people, {:array, :string}, default: [], null: false
      add :likes, :integer, default: 0, null: false
      add :likes_previous, :integer, default: 0, null: false
      add :likes_people, {:array, :string}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create index(:podcast_popularity, [:score], prefix: "site")
    create index(:podcast_popularity, [:plays], prefix: "site")
    create index(:podcast_popularity, [:likes], prefix: "site")

    # Indexes for trending calculations (order by desc for trending)
    create index(:podcast_popularity, [:score, :score_previous], prefix: "site")
    create index(:podcast_popularity, [:plays, :plays_previous], prefix: "site")
    create index(:podcast_popularity, [:likes, :likes_previous], prefix: "site")
  end
end
