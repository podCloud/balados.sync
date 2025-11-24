defmodule BaladosSyncProjections.Repo.Migrations.RenameUserTokensToPlayTokens do
  use Ecto.Migration

  def up do
    # Rename user_tokens to play_tokens
    rename table(:user_tokens, prefix: "users"), to: table(:play_tokens, prefix: "users")
  end

  def down do
    # Rename play_tokens back to user_tokens
    rename table(:play_tokens, prefix: "users"), to: table(:user_tokens, prefix: "users")
  end
end
