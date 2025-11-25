defmodule BaladosSyncProjections.Repo.Migrations.MoveSystemTables do
  use Ecto.Migration

  def up do
    # Déplacer les tables de données permanentes (non event-sourced) du schéma "users" vers "system"
    # Les index et contraintes sont automatiquement déplacés avec les tables

    execute "ALTER TABLE users.users SET SCHEMA system"
    execute "ALTER TABLE users.app_tokens SET SCHEMA system"
    execute "ALTER TABLE users.play_tokens SET SCHEMA system"
  end

  def down do
    # Remettre les tables dans le schéma "users"
    execute "ALTER TABLE system.users SET SCHEMA users"
    execute "ALTER TABLE system.app_tokens SET SCHEMA users"
    execute "ALTER TABLE system.play_tokens SET SCHEMA users"
  end
end
