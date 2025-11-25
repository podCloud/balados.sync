defmodule BaladosSyncProjections.Repo.Migrations.CreateSchemas do
  use Ecto.Migration

  def up do
    execute "CREATE SCHEMA IF NOT EXISTS events"
    execute "CREATE SCHEMA IF NOT EXISTS users"
    execute "CREATE SCHEMA IF NOT EXISTS site"
  end

  def down do
    execute "DROP SCHEMA IF EXISTS site CASCADE"
    execute "DROP SCHEMA IF EXISTS users CASCADE"
    execute "DROP SCHEMA IF EXISTS events CASCADE"
  end
end
