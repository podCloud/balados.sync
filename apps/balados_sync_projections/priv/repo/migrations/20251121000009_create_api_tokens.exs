defmodule BaladosSyncProjections.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :app_name, :string, null: false
      add :app_image, :text
      add :app_url, :text
      add :public_key, :text, null: false
      # JWT ID pour révocation
      add :token_jti, :string, null: false
      add :scopes, {:array, :string}, default: []
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_tokens, [:token_jti], prefix: "users")
    create index(:api_tokens, [:user_id], prefix: "users")

    create index(:api_tokens, [:user_id, :revoked_at],
             prefix: "users",
             where: "revoked_at IS NULL"
           )
  end
end
