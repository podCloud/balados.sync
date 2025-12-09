defmodule BaladosSyncProjections.Schemas.PlayToken do
  @moduledoc """
  Schema for simple bearer tokens used for play gateway authentication.

  Play tokens are simple bearer tokens that allow unauthenticated access
  to the play gateway for tracking listens without full app authorization.
  These are used by podcast players that redirect through the play gateway.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"
  schema "play_tokens" do
    field :user_id, :string
    field :token, :string
    # "My iPhone", "Desktop", etc.
    field :name, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a play token.
  """
  def changeset(play_token, attrs) do
    play_token
    |> cast(attrs, [:user_id, :token, :name, :last_used_at, :revoked_at, :expires_at])
    |> validate_required([:user_id, :token])
    |> unique_constraint(:token)
  end

  @doc """
  Generates a secure random token.
  """
  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Changeset for updating the last_used_at timestamp.
  """
  def touch_changeset(play_token) do
    change(play_token, last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for revoking a token.
  """
  def revoke_changeset(play_token) do
    change(play_token, revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Checks if a token has expired.

  Returns true if the token has an expiration date and it's in the past.
  Returns false if the token has no expiration or if the expiration is in the future.
  """
  def expired?(play_token) do
    case play_token.expires_at do
      nil -> false
      expires_at -> DateTime.compare(expires_at, DateTime.utc_now()) == :lt
    end
  end

  @doc """
  Calculates an expiration date based on days from now.

  Defaults to 365 days if not provided.
  """
  def calculate_expiration(days_from_now \\ 365)
      when is_integer(days_from_now) and days_from_now > 0 do
    DateTime.utc_now()
    |> DateTime.add(days_from_now * 86400, :second)
    |> DateTime.truncate(:second)
  end
end
