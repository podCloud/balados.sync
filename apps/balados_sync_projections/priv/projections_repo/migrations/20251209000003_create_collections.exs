defmodule BaladosSyncProjections.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    # Create collections table
    create table(:collections, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :user_id, :text, null: false
      add :title, :text, null: false
      add :is_default, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Index for user lookups
    create index(:collections, [:user_id], prefix: "users")

    # Unique constraint: only one default collection per user (not deleted)
    create unique_index(:collections, [:user_id],
      prefix: "users",
      where: "is_default = true AND deleted_at IS NULL",
      name: :collections_user_id_default_unique
    )

    # Create collection_subscriptions join table
    create table(:collection_subscriptions, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :collection_id, references(:collections, type: :binary_id, on_delete: :delete_all),
        null: false
      add :rss_source_feed, :text, null: false

      timestamps(type: :utc_datetime)
    end

    # Index for collection lookups
    create index(:collection_subscriptions, [:collection_id], prefix: "users")

    # Unique constraint: feed can only be in a collection once
    create unique_index(:collection_subscriptions, [:collection_id, :rss_source_feed],
      prefix: "users"
    )
  end
end
