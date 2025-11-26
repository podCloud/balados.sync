defmodule BaladosSyncProjections.Repo.Migrations.CreatePublicEvents do
  use Ecto.Migration

  def change do
    create table(:public_events, primary_key: false, prefix: "public") do
      add :id, :binary_id, primary_key: true
      # null si anonymous
      add :user_id, :string
      add :event_type, :string, null: false
      add :rss_source_feed, :text
      add :rss_source_item, :text
      add :privacy, :string, null: false
      add :event_data, :jsonb, default: "{}"
      add :event_timestamp, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:public_events, [:event_type], prefix: "public")
    create index(:public_events, [:user_id], prefix: "public", where: "user_id IS NOT NULL")
    create index(:public_events, [:rss_source_feed], prefix: "public")
    create index(:public_events, [:rss_source_item], prefix: "public")
    create index(:public_events, [:event_timestamp], prefix: "public")
    create index(:public_events, [:privacy], prefix: "public")

    # Index composite pour feed timeline
    create index(:public_events, [:event_timestamp, :event_type],
             prefix: "public",
             name: :public_events_timeline_idx
           )

    # Index pour activité user
    create index(:public_events, [:user_id, :event_timestamp],
             prefix: "public",
             where: "user_id IS NOT NULL"
           )
  end
end
