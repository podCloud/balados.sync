defmodule BaladosSyncProjections.Repo.Migrations.AddDeletedAtToPlaylists do
  use Ecto.Migration

  def change do
    alter table(:playlists, prefix: "users") do
      add :deleted_at, :utc_datetime
    end

    # Index for active playlists (not deleted)
    create index(:playlists, [:user_id, :deleted_at],
             prefix: "users",
             where: "deleted_at IS NULL",
             name: "playlists_active_idx"
           )
  end
end
