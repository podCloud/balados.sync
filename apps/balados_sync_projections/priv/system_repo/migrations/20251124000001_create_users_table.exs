defmodule BaladosSyncProjections.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false, prefix: "system") do
      add :id, :string, primary_key: true
      add :email, :string
      add :username, :string
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :locked_at, :utc_datetime
      add :failed_login_attempts, :integer, default: 0
      add :is_admin, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email], prefix: "system", where: "email IS NOT NULL")
    create unique_index(:users, [:username], prefix: "system", where: "username IS NOT NULL")
    create index(:users, [:is_admin], prefix: "system")
  end
end
