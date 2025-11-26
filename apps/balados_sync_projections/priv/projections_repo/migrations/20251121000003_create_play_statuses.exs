defmodule BaladosSyncProjections.Repo.Migrations.CreatePlayStatuses do
  use Ecto.Migration

  def change do
    create table(:play_statuses, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :rss_source_feed, :text
      add :rss_source_item, :text, null: false
      add :rss_feed_title, :text
      add :rss_item_title, :text
      add :played, :boolean, default: false
      add :position, :integer, default: 0
      add :rss_enclosure, :jsonb
      add :updated_at, :utc_datetime, null: false
    end

    create unique_index(:play_statuses, [:user_id, :rss_source_item], prefix: "users")
    create index(:play_statuses, [:user_id], prefix: "users")
    create index(:play_statuses, [:rss_source_item], prefix: "users")
    create index(:play_statuses, [:user_id, :updated_at], prefix: "users")

    # Index pour les épisodes en cours de lecture
    create index(:play_statuses, [:user_id, :played],
             prefix: "users",
             where: "played = false AND position > 0"
           )
  end
end
