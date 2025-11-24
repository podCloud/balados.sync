defmodule BaladosSyncProjections.Schemas.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users.api_tokens" do
    field :user_id, :string
    field :app_name, :string
    field :app_image, :string
    field :app_url, :string
    field :public_key, :string
    field :token_jti, :string
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new API token.
  """
  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:user_id, :app_name, :app_image, :app_url, :public_key, :token_jti, :scopes, :last_used_at, :revoked_at])
    |> validate_required([:user_id, :app_name, :public_key, :token_jti])
    |> unique_constraint(:token_jti)
    |> validate_length(:app_name, min: 1, max: 255)
    |> validate_public_key()
  end

  @doc """
  Changeset for updating the last_used_at timestamp.
  """
  def touch_changeset(api_token) do
    change(api_token, last_used_at: DateTime.utc_now())
  end

  @doc """
  Changeset for revoking a token.
  """
  def revoke_changeset(api_token) do
    change(api_token, revoked_at: DateTime.utc_now())
  end

  defp validate_public_key(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      case :public_key.pem_decode(public_key) do
        [] -> [public_key: "must be a valid PEM-encoded RSA public key"]
        _ -> []
      end
    rescue
      _ -> [public_key: "must be a valid PEM-encoded RSA public key"]
    end)
  end
end
