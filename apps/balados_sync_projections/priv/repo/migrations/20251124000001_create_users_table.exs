defmodule BaladosSyncProjections.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :username, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime
      add :locked_at, :utc_datetime
      add :failed_login_attempts, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email], prefix: "users")
    create unique_index(:users, [:username], prefix: "users")
    create index(:users, [:confirmed_at], prefix: "users")
  end
end
