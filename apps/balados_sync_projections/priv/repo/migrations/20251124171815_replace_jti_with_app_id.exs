defmodule BaladosSyncProjections.Repo.Migrations.ReplaceJtiWithAppId do
  use Ecto.Migration

  def up do
    # Rename api_tokens to app_tokens
    rename table(:api_tokens, prefix: "users"), to: table(:app_tokens, prefix: "users")

    # Drop the old unique index on token_jti (need to use the actual index name after table rename)
    execute("DROP INDEX IF EXISTS users.api_tokens_token_jti_index")

    # Rename token_jti column to app_id
    rename table(:app_tokens, prefix: "users"), :token_jti, to: :app_id

    # Create unique index on user_id + app_id combination
    # This ensures one authorization per user per app
    create unique_index(:app_tokens, [:user_id, :app_id], prefix: "users")

    # Create index on app_id + public_key for app popularity tracking
    create index(:app_tokens, [:app_id, :public_key], prefix: "users")
  end

  def down do
    # Remove new indexes
    drop index(:app_tokens, [:app_id, :public_key], prefix: "users")
    drop unique_index(:app_tokens, [:user_id, :app_id], prefix: "users")

    # Rename app_id back to token_jti
    rename table(:app_tokens, prefix: "users"), :app_id, to: :token_jti

    # Recreate old unique index
    create unique_index(:app_tokens, [:token_jti], prefix: "users")

    # Rename app_tokens back to api_tokens
    rename table(:app_tokens, prefix: "users"), to: table(:api_tokens, prefix: "users")
  end
end
