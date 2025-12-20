defmodule BaladosSyncProjections.SystemRepo.Migrations.AddPodcastOwnershipTables do
  @moduledoc """
  Adds podcast ownership infrastructure:
  - admin_user_ids to enriched_podcasts (multi-admin support)
  - podcast_ownership_claims table for verification flow
  - user_podcast_settings table for visibility preferences
  """
  use Ecto.Migration

  def change do
    # Add admin_user_ids to enriched_podcasts (from PR #107)
    alter table(:enriched_podcasts, prefix: "system") do
      add :admin_user_ids, {:array, :string}, default: [], null: false
    end

    create index(:enriched_podcasts, [:admin_user_ids], prefix: "system", using: "GIN")

    # Create podcast_ownership_claims table for verification workflow
    create table(:podcast_ownership_claims, primary_key: false, prefix: "system") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :enriched_podcast_id, references(:enriched_podcasts, type: :binary_id, prefix: "system", on_delete: :delete_all)
      add :feed_url, :text, null: false
      add :verification_code, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :verified_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      add :failure_reason, :text
      add :verification_attempts, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:podcast_ownership_claims, [:user_id], prefix: "system")
    create index(:podcast_ownership_claims, [:enriched_podcast_id], prefix: "system")
    create index(:podcast_ownership_claims, [:verification_code], prefix: "system")
    create index(:podcast_ownership_claims, [:status], prefix: "system")
    create index(:podcast_ownership_claims, [:expires_at], prefix: "system", where: "status = 'pending'")

    # Prevent duplicate pending claims per user per podcast
    create unique_index(:podcast_ownership_claims, [:user_id, :feed_url],
      prefix: "system",
      where: "status = 'pending'",
      name: :unique_pending_claim_per_user_podcast
    )

    # Create user_podcast_settings for visibility preferences
    create table(:user_podcast_settings, primary_key: false, prefix: "system") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :enriched_podcast_id, references(:enriched_podcasts, type: :binary_id, prefix: "system", on_delete: :delete_all), null: false
      add :visibility, :string, null: false, default: "private"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_podcast_settings, [:user_id, :enriched_podcast_id], prefix: "system")
    create index(:user_podcast_settings, [:user_id, :visibility], prefix: "system")
  end
end
