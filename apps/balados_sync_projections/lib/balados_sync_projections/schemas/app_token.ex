defmodule BaladosSyncProjections.Schemas.AppToken do
  @moduledoc """
  Schema for third-party app authorizations using JWT-based authentication.

  Apps are identified by their app_id (from JWT 'iss' field) and public key.
  Users authorize apps, allowing them to make API requests on their behalf
  within the granted scopes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"
  schema "app_tokens" do
    field :user_id, :string
    field :app_name, :string
    field :app_image, :string
    field :app_url, :string
    field :public_key, :string
    field :app_id, :string
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an app token authorization.
  """
  def changeset(app_token, attrs) do
    app_token
    |> cast(attrs, [
      :user_id,
      :app_name,
      :app_image,
      :app_url,
      :public_key,
      :app_id,
      :scopes,
      :last_used_at,
      :revoked_at
    ])
    |> validate_required([:user_id, :app_name, :public_key, :app_id])
    |> unique_constraint([:user_id, :app_id], name: :app_tokens_user_id_app_id_index)
    |> validate_length(:app_name, min: 1, max: 255)
    |> validate_public_key()
    |> validate_scopes()
  end

  @doc """
  Changeset for updating the last_used_at timestamp.
  """
  def touch_changeset(app_token) do
    change(app_token, last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for revoking a token.
  """
  def revoke_changeset(app_token) do
    change(app_token, revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp validate_public_key(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      try do
        case :public_key.pem_decode(public_key) do
          [] -> [public_key: "must be a valid PEM-encoded RSA public key"]
          _ -> []
        end
      rescue
        _ -> [public_key: "must be a valid PEM-encoded RSA public key"]
      end
    end)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      if is_list(scopes) and Enum.all?(scopes, &is_binary/1) do
        []
      else
        [scopes: "must be a list of strings"]
      end
    end)
  end
end
