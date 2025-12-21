defmodule BaladosSyncProjections.SystemRepo.Migrations.AddEmailVerification do
  @moduledoc """
  Adds email verification as an alternative method for podcast ownership claims.

  Stores pending email verifications with rate limiting and expiration tracking.
  """
  use Ecto.Migration

  def change do
    create table(:email_verifications, primary_key: false, prefix: "system") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :claim_id, references(:podcast_ownership_claims, type: :binary_id, prefix: "system", on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :email_source, :string, null: false
      add :verification_code, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :verified_at, :utc_datetime
      add :attempts, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:email_verifications, [:user_id], prefix: "system")
    create index(:email_verifications, [:claim_id], prefix: "system")
    create index(:email_verifications, [:verification_code], prefix: "system")
    create index(:email_verifications, [:status], prefix: "system")
    create index(:email_verifications, [:expires_at], prefix: "system", where: "status = 'pending'")

    # Rate limiting index: count verifications per email in last hour
    create index(:email_verifications, [:email, :inserted_at], prefix: "system")

    # Prevent duplicate pending verifications per claim
    create unique_index(:email_verifications, [:claim_id],
      prefix: "system",
      where: "status = 'pending'",
      name: :unique_pending_email_verification_per_claim
    )

    # Add verification_method to claims to track which method was used
    alter table(:podcast_ownership_claims, prefix: "system") do
      add :verification_method, :string, default: "rss"
    end
  end
end
