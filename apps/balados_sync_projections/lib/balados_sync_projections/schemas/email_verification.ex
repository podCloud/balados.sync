defmodule BaladosSyncProjections.Schemas.EmailVerification do
  @moduledoc """
  Schema for email-based podcast ownership verification.

  Tracks email verification codes sent to addresses found in podcast RSS feeds.

  Status flow:
  - pending: Verification code generated, awaiting send or entry
  - sent: Email sent, awaiting user to enter code
  - verified: Code validated successfully
  - expired: Code expired before verification
  - failed: Too many failed attempts

  This is a system table (not event-sourced), managed directly via Ecto.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"

  @valid_statuses ~w(pending sent verified expired failed)
  @code_length 6
  @default_expiration_minutes 30
  @max_attempts 5

  schema "email_verifications" do
    field :user_id, :string
    field :email, :string
    field :email_source, :string
    field :verification_code, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :verified_at, :utc_datetime
    field :attempts, :integer, default: 0

    belongs_to :claim, BaladosSyncProjections.Schemas.PodcastOwnershipClaim, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(verification, attrs) do
    verification
    |> cast(attrs, [
      :user_id,
      :claim_id,
      :email,
      :email_source,
      :verification_code,
      :status,
      :expires_at,
      :sent_at,
      :verified_at,
      :attempts
    ])
    |> validate_required([:user_id, :claim_id, :email, :email_source, :verification_code, :expires_at])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_format(:email, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)
  end

  @doc """
  Generates a 6-digit numeric verification code.
  """
  def generate_verification_code do
    :crypto.strong_rand_bytes(4)
    |> :binary.decode_unsigned()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(@code_length, "0")
  end

  @doc """
  Creates a new pending email verification.
  Default expiration: 30 minutes from now.
  """
  def create_changeset(user_id, claim_id, email, email_source, opts \\ []) do
    expiration_minutes = Keyword.get(opts, :expiration_minutes, @default_expiration_minutes)
    expires_at = DateTime.utc_now() |> DateTime.add(expiration_minutes * 60, :second)

    %__MODULE__{}
    |> cast(
      %{
        user_id: user_id,
        claim_id: claim_id,
        email: email,
        email_source: email_source,
        verification_code: generate_verification_code(),
        status: "pending",
        expires_at: expires_at,
        attempts: 0
      },
      [:user_id, :claim_id, :email, :email_source, :verification_code, :status, :expires_at, :attempts]
    )
    |> validate_required([:user_id, :claim_id, :email, :email_source, :verification_code, :expires_at])
  end

  @doc """
  Marks verification as sent.
  """
  def mark_sent_changeset(verification) do
    verification
    |> change(%{
      status: "sent",
      sent_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks verification as verified.
  """
  def verify_changeset(verification) do
    verification
    |> change(%{
      status: "verified",
      verified_at: DateTime.utc_now()
    })
  end

  @doc """
  Increments attempt count. Returns failed status if max attempts reached.
  """
  def increment_attempts_changeset(verification) do
    new_attempts = (verification.attempts || 0) + 1

    if new_attempts >= @max_attempts do
      verification
      |> change(%{
        status: "failed",
        attempts: new_attempts
      })
    else
      verification
      |> change(%{attempts: new_attempts})
    end
  end

  @doc """
  Marks verification as expired.
  """
  def expire_changeset(verification) do
    verification
    |> change(%{status: "expired"})
  end

  @doc """
  Returns the maximum number of attempts allowed.
  """
  def max_attempts, do: @max_attempts

  @doc """
  Returns the list of valid statuses.
  """
  def valid_statuses, do: @valid_statuses
end
