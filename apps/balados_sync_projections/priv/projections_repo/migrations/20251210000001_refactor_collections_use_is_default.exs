defmodule BaladosSyncProjections.Repo.Migrations.RefactorCollectionsUseIsDefault do
  use Ecto.Migration

  def change do
    # Step 1: Add is_default column (default false)
    alter table(:collections, prefix: "users") do
      add :is_default, :boolean, default: false, null: false
    end

    # Step 2: Migrate existing data - set is_default=true for slug='all'
    execute("UPDATE users.collections SET is_default = true WHERE slug = 'all'")

    # Step 3: Remove slug column
    alter table(:collections, prefix: "users") do
      remove :slug
    end

    # Step 4: Add unique constraint - only one default collection per user
    # Note: Default collections (is_default=true) cannot be deleted
    create unique_index(:collections, [:user_id, :is_default],
             prefix: "users",
             where: "is_default = true",
             name: "collections_user_id_is_default_index"
           )
  end
end
