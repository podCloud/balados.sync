defmodule BaladosSyncProjections.Repo.Migrations.CreatePlayTokens do
  use Ecto.Migration

  def change do
    create table(:play_tokens, primary_key: false, prefix: "system") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :token, :string, null: false
      add :name, :string
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:play_tokens, [:token], prefix: "system")
    create index(:play_tokens, [:user_id], prefix: "system")

    create index(:play_tokens, [:user_id, :revoked_at],
             prefix: "system",
             where: "revoked_at IS NULL"
           )

    create index(:play_tokens, [:token, :revoked_at],
             prefix: "system",
             where: "revoked_at IS NULL"
           )
  end
end
