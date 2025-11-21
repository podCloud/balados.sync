
defmodule BaladosSyncProjections.Repo.Migrations.CreatePublicEvents do
  use Ecto.Migration

  def change do
    create table(:public_events, primary_key: false, prefix: "site") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string  # null si anonymous
      add :event_type, :string, null: false
      add :rss_source_feed, :text
      add :rss_source_item, :text
      add :privacy, :string, null: false
      add :event_data, :jsonb, default: "{}"
      add :event_timestamp, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:public_events, [:event_type], prefix: "site")
    create index(:public_events, [:user_id], prefix: "site", where: "user_id IS NOT NULL")
    create index(:public_events, [:rss_source_feed], prefix: "site")
    create index(:public_events, [:rss_source_item], prefix: "site")
    create index(:public_events, [:event_timestamp], prefix: "site")
    create index(:public_events, [:privacy], prefix: "site")
    
    # Index composite pour feed timeline
    create index(:public_events, [:event_timestamp, :event_type], 
      prefix: "site",
      name: :public_events_timeline_idx
    )
    
    # Index pour activité user
    create index(:public_events, [:user_id, :event_timestamp], 
      prefix: "site",
      where: "user_id IS NOT NULL"
    )
  end
end

