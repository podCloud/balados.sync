defmodule BaladosSyncProjections.Repo.Migrations.CreateAppTokens do
  use Ecto.Migration

  def change do
    create table(:app_tokens, primary_key: false, prefix: "system") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :app_id, :string, null: false
      add :token_name, :string
      add :token_scopes, {:array, :string}, default: [], null: false
      add :public_key, :text, null: false
      add :revoked_at, :utc_datetime
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:app_tokens, [:app_id], prefix: "system")
    create index(:app_tokens, [:user_id], prefix: "system")
  end
end
