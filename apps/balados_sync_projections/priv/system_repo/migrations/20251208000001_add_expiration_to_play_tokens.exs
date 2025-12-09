defmodule BaladosSyncProjections.Repo.Migrations.AddExpirationToPlayTokens do
  use Ecto.Migration

  def change do
    alter table(:play_tokens, prefix: "system") do
      add :expires_at, :utc_datetime
    end

    # Create index for efficient expiration queries
    create index(:play_tokens, [:expires_at],
             prefix: "system",
             where: "expires_at IS NOT NULL AND revoked_at IS NULL"
           )
  end
end
