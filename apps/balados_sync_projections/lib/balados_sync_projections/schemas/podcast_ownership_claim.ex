defmodule BaladosSyncProjections.Schemas.PodcastOwnershipClaim do
  @moduledoc """
  Schema for podcast ownership verification claims.

  Tracks the verification flow for users claiming administrative ownership
  of a podcast by proving they control its RSS feed.

  Status flow:
  - pending: Initial state, awaiting verification
  - verified: Verification successful, user is now an admin
  - failed: Verification code not found in feed
  - expired: Verification code expired before successful verification
  - cancelled: User cancelled the claim request

  This is a system table (not event-sourced), managed directly via Ecto.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"

  @valid_statuses ~w(pending verified failed expired cancelled)

  schema "podcast_ownership_claims" do
    field :user_id, :string
    field :feed_url, :string
    field :verification_code, :string
    field :status, :string, default: "pending"
    field :verified_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :failure_reason, :string
    field :verification_attempts, :integer, default: 0
    field :verification_method, :string, default: "rss"

    belongs_to :enriched_podcast, BaladosSyncProjections.Schemas.EnrichedPodcast, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [
      :user_id,
      :feed_url,
      :verification_code,
      :status,
      :verified_at,
      :expires_at,
      :failure_reason,
      :verification_attempts,
      :verification_method,
      :enriched_podcast_id
    ])
    |> validate_required([:user_id, :feed_url, :verification_code, :expires_at])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Generates a new verification code in the format: balados-verify-<random_hex>
  Uses cryptographically secure random generation.
  """
  def generate_verification_code do
    random_bytes = :crypto.strong_rand_bytes(16)
    random_hex = Base.encode16(random_bytes, case: :lower)
    "balados-verify-#{random_hex}"
  end

  @doc """
  Creates a new pending claim with auto-generated verification code.
  Default expiration: 48 hours from now.
  """
  def create_changeset(user_id, feed_url, opts \\ []) do
    expiration_hours = Keyword.get(opts, :expiration_hours, 48)
    expires_at = DateTime.utc_now() |> DateTime.add(expiration_hours * 3600, :second)

    %__MODULE__{}
    |> cast(
      %{
        user_id: user_id,
        feed_url: feed_url,
        verification_code: generate_verification_code(),
        status: "pending",
        expires_at: expires_at,
        verification_attempts: 0
      },
      [:user_id, :feed_url, :verification_code, :status, :expires_at, :verification_attempts]
    )
    |> validate_required([:user_id, :feed_url, :verification_code, :expires_at])
  end

  @doc """
  Marks claim as verified with enriched podcast association.
  """
  def verify_changeset(claim, enriched_podcast_id) do
    claim
    |> change(%{
      status: "verified",
      verified_at: DateTime.utc_now(),
      enriched_podcast_id: enriched_podcast_id
    })
  end

  @doc """
  Marks claim as failed with reason.
  """
  def fail_changeset(claim, reason) do
    claim
    |> change(%{
      status: "failed",
      failure_reason: reason,
      verification_attempts: (claim.verification_attempts || 0) + 1
    })
  end

  @doc """
  Increments verification attempts without changing status.
  Used when verification fails but user can retry.
  """
  def increment_attempts_changeset(claim) do
    claim
    |> change(%{verification_attempts: (claim.verification_attempts || 0) + 1})
  end

  @doc """
  Marks claim as expired.
  """
  def expire_changeset(claim) do
    claim
    |> change(%{status: "expired"})
  end

  @doc """
  Marks claim as cancelled.
  """
  def cancel_changeset(claim) do
    claim
    |> change(%{status: "cancelled"})
  end

  @doc """
  Returns the list of valid statuses.
  """
  def valid_statuses, do: @valid_statuses
end
