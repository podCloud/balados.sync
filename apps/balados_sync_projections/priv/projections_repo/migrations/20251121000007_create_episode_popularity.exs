defmodule BaladosSyncProjections.Repo.Migrations.CreateEpisodePopularity do
  use Ecto.Migration

  def change do
    create table(:episode_popularity, primary_key: false, prefix: "public") do
      add :rss_source_item, :text, primary_key: true
      add :rss_source_feed, :text
      add :episode_title, :text
      add :episode_author, :text
      add :episode_description, :text
      add :episode_cover, :jsonb
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

    create index(:episode_popularity, [:rss_source_feed], prefix: "public")
    create index(:episode_popularity, [:score], prefix: "public")
    create index(:episode_popularity, [:plays], prefix: "public")
    create index(:episode_popularity, [:likes], prefix: "public")

    # Indexes for trending calculations
    create index(:episode_popularity, [:score, :score_previous], prefix: "public")
    create index(:episode_popularity, [:plays, :plays_previous], prefix: "public")
    create index(:episode_popularity, [:likes, :likes_previous], prefix: "public")

    # Index composite pour top episodes d'un podcast
    create index(:episode_popularity, [:rss_source_feed, :score], prefix: "public")
    create index(:episode_popularity, [:rss_source_feed, :plays], prefix: "public")
  end
end
