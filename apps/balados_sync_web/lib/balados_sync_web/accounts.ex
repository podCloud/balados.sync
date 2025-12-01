defmodule BaladosSyncWeb.Accounts do
  @moduledoc """
  The Accounts context for user authentication and management.
  """

  import Ecto.Query, warn: false
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.User

  ## User registration

  @doc """
  Registers a new user.

  ## Examples

      iex> register_user(%{email: "user@example.com", username: "user", password: "ValidPassword123!"})
      {:ok, %User{}}

      iex> register_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> SystemRepo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## User authentication

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("user@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    SystemRepo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("user@example.com", "correct_password")
      {:ok, %User{}}

      iex> get_user_by_email_and_password("user@example.com", "wrong_password")
      {:error, :invalid_credentials}

      iex> get_user_by_email_and_password("user@example.com", "password_when_locked")
      {:error, :locked}

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = SystemRepo.get_by(User, email: email)
    verify_user_password(user, password)
  end

  @doc """
  Gets a user by username and password.

  ## Examples

      iex> get_user_by_username_and_password("username", "correct_password")
      {:ok, %User{}}

      iex> get_user_by_username_and_password("username", "wrong_password")
      {:error, :invalid_credentials}

  """
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = SystemRepo.get_by(User, username: username)
    verify_user_password(user, password)
  end

  defp verify_user_password(user, password) do
    cond do
      # User doesn't exist
      is_nil(user) ->
        # Call no_user_verify to prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      # Account is locked
      not is_nil(user.locked_at) ->
        {:error, :locked}

      # Password is valid
      User.valid_password?(user, password) ->
        # Reset failed attempts on successful login
        {:ok, updated_user} =
          user
          |> User.reset_failed_attempts_changeset()
          |> SystemRepo.update()

        {:ok, updated_user}

      # Password is invalid
      true ->
        # Increment failed attempts
        user
        |> User.increment_failed_attempts_changeset()
        |> SystemRepo.update()

        {:error, :invalid_credentials}
    end
  end

  @doc """
  Gets a single user by id.

  ## Examples

      iex> get_user("123")
      %User{}

      iex> get_user("456")
      nil

  """
  def get_user(id) do
    SystemRepo.get(User, id)
  end

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    SystemRepo.get_by(User, username: username)
  end

  ## User confirmation

  @doc """
  Confirms a user account.
  """
  def confirm_user(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> SystemRepo.update()
  end

  ## Account locking

  @doc """
  Locks a user account.
  """
  def lock_user(%User{} = user) do
    user
    |> User.lock_changeset()
    |> SystemRepo.update()
  end

  @doc """
  Unlocks a user account.
  """
  def unlock_user(%User{} = user) do
    user
    |> User.unlock_changeset()
    |> SystemRepo.update()
  end

  ## Admin functions

  @doc """
  Checks if any users exist in the system.
  """
  def any_users_exist? do
    SystemRepo.exists?(User)
  end

  @doc """
  Counts total number of users.
  """
  def count_users do
    SystemRepo.aggregate(User, :count, :id)
  end

  @doc """
  Registers the first admin user during initial setup.
  """
  def register_admin_user(attrs) do
    require Logger

    changeset =
      %User{}
      |> User.registration_changeset(attrs)
      |> Ecto.Changeset.put_change(:is_admin, true)

    Logger.debug("Register admin changeset changes: #{inspect(changeset.changes, pretty: true)}")
    Logger.debug("Register admin changeset data: #{inspect(changeset.data, pretty: true)}")

    # Log each field and its value before insert
    Enum.each(changeset.changes, fn {key, value} ->
      Logger.debug("  #{key}: #{inspect(value)}")
    end)

    SystemRepo.insert(changeset)
  end

  @doc """
  Checks if a user is an admin.
  """
  def admin?(%User{is_admin: true}), do: true
  def admin?(_), do: false
end
