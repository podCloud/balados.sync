defmodule BaladosSyncProjections.Repo.Migrations.CreateUserTokens do
  use Ecto.Migration

  def change do
    create table(:user_tokens, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :token, :string, null: false
      add :name, :string
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_tokens, [:token], prefix: "users")
    create index(:user_tokens, [:user_id], prefix: "users")

    create index(:user_tokens, [:user_id, :revoked_at],
             prefix: "users",
             where: "revoked_at IS NULL"
           )

    create index(:user_tokens, [:token, :revoked_at],
             prefix: "users",
             where: "revoked_at IS NULL"
           )
  end
end
