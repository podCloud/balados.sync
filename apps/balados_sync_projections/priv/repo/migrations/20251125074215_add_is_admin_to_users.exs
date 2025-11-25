defmodule BaladosSyncProjections.Repo.Migrations.AddIsAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users, prefix: "users") do
      add :is_admin, :boolean, default: false, null: false
    end

    # Index pour les requêtes admin
    create index(:users, [:is_admin], prefix: "users")
  end
end
