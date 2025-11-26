defmodule BaladosSyncProjections.Repo.Migrations.CreatePlaylists do
  use Ecto.Migration

  def change do
    create table(:playlists, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create index(:playlists, [:user_id], prefix: "users")
    create index(:playlists, [:user_id, :name], prefix: "users")

    create table(:playlist_items, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true

      add :playlist_id,
          references(:playlists, type: :binary_id, on_delete: :delete_all, prefix: "users"),
          null: false

      add :rss_source_feed, :text
      add :rss_source_item, :text, null: false
      add :item_title, :text
      add :feed_title, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:playlist_items, [:playlist_id], prefix: "users")
    create index(:playlist_items, [:rss_source_item], prefix: "users")

    # Index pour les items actifs (non supprimés)
    create index(:playlist_items, [:playlist_id, :deleted_at],
             prefix: "users",
             where: "deleted_at IS NULL"
           )
  end
end
