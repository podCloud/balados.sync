defmodule BaladosSyncProjections.Schemas.User do
  @moduledoc """
  User schema with Argon2id password hashing.

  Passwords are hashed with Argon2id (OWASP 2025 recommended) which provides
  memory-hard protection against GPU-based attacks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  require Logger

  # Argon2id configuration (OWASP 2025 recommendations)
  # t_cost: 3 iterations
  # m_cost: 16 = 64 MiB memory (2^16 KiB)
  # parallelism: 1 thread
  @argon2_opts [t_cost: 3, m_cost: 16, parallelism: 1]

  @primary_key {:id, :string, autogenerate: {Ecto.UUID, :generate, []}}
  @schema_prefix "system"
  schema "users" do
    field :email, :string
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :locked_at, :utc_datetime
    field :failed_login_attempts, :integer, default: 0
    field :is_admin, :boolean, default: false

    # Profile fields
    field :public_name, :string
    field :avatar_url, :string
    field :public_profile_enabled, :boolean, default: false
    field :bio, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Security considerations

  - Password must be at least 12 characters
  - Password is hashed using Argon2id (OWASP 2025 recommended)
  - Email is downcased and trimmed
  - Username is trimmed and validated for format
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :username, :password, :password_confirmation])
    |> validate_email(opts)
    |> validate_username()
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_-]+$/,
      message: "must contain only letters, numbers, hyphens and underscores"
    )
    |> unique_constraint(:username)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    |> validate_format(:password, ~r/[0-9]/, message: "at least one digit")
    |> validate_format(:password, ~r/[!@#$%^&*(),.?":{}|<>]/,
      message: "at least one special character"
    )
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password, @argon2_opts))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, BaladosSyncCore.SystemRepo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Locks the account by setting `locked_at`.
  """
  def lock_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, locked_at: now, failed_login_attempts: 0)
  end

  @doc """
  Unlocks the account by clearing `locked_at`.
  """
  def unlock_changeset(user) do
    change(user, locked_at: nil, failed_login_attempts: 0)
  end

  @doc """
  Increments failed login attempts.
  """
  def increment_failed_attempts_changeset(user) do
    attempts = (user.failed_login_attempts || 0) + 1

    # Lock account after 5 failed attempts
    if attempts >= 5 do
      user
      |> change(failed_login_attempts: attempts)
      |> lock_changeset()
    else
      change(user, failed_login_attempts: attempts)
    end
  end

  @doc """
  Resets failed login attempts after successful login.
  """
  def reset_failed_attempts_changeset(user) do
    change(user, failed_login_attempts: 0)
  end

  @doc """
  A user changeset for updating profile settings.

  Allows updating public_name, bio, and public_profile_enabled.
  Avatar URL is handled separately via avatar upload.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:public_name, :bio, :public_profile_enabled])
    |> validate_length(:public_name, max: 100)
    |> validate_length(:bio, max: 500)
  end

  @doc """
  A user changeset for updating the avatar URL.
  """
  def avatar_changeset(user, attrs) do
    user
    |> cast(attrs, [:avatar_url])
    |> validate_length(:avatar_url, max: 500)
  end

  @doc """
  Makes a user an admin.
  """
  def make_admin_changeset(user) do
    change(user, is_admin: true)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Argon2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{}, [])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
