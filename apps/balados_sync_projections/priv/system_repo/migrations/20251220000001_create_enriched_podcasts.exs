defmodule BaladosSyncProjections.Repo.Migrations.CreateEnrichedPodcasts do
  use Ecto.Migration

  def change do
    create table(:enriched_podcasts, primary_key: false, prefix: "system") do
      add :id, :binary_id, primary_key: true
      add :feed_url, :string, null: false
      add :slug, :string, null: false
      add :background_color, :string
      add :links, :jsonb, default: "[]"
      add :created_by_user_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:enriched_podcasts, [:slug], prefix: "system")
    create unique_index(:enriched_podcasts, [:feed_url], prefix: "system")
    create index(:enriched_podcasts, [:created_by_user_id], prefix: "system")
  end
end
