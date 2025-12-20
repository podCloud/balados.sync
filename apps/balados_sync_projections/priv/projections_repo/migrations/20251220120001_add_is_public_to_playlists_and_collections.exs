defmodule BaladosSyncProjections.ProjectionsRepo.Migrations.AddIsPublicToPlaylistsAndCollections do
  use Ecto.Migration

  def change do
    # Add is_public to playlists
    alter table(:playlists, prefix: "users") do
      add :is_public, :boolean, default: false, null: false
    end

    # Add is_public to collections
    alter table(:collections, prefix: "users") do
      add :is_public, :boolean, default: false, null: false
    end

    # Add index for efficient querying of public playlists
    create index(:playlists, [:user_id, :is_public], prefix: "users")

    # Add index for efficient querying of public collections
    create index(:collections, [:user_id, :is_public], prefix: "users")
  end
end
