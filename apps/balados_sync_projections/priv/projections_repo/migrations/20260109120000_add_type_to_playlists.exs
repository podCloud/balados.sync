defmodule BaladosSyncProjections.ProjectionsRepo.Migrations.AddTypeToPlaylists do
  use Ecto.Migration

  def change do
    alter table(:playlists, prefix: "users") do
      add :type, :string, default: "playlist", null: false
    end

    # Index for efficient filtering by user and type
    create index(:playlists, [:user_id, :type], prefix: "users")
  end
end
