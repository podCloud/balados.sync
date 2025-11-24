defmodule BaladosSyncProjections.Schemas.UserToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "users"
  schema "user_tokens" do
    field :user_id, :string
    field :token, :string
    # "My iPhone", "Desktop", etc.
    field :name, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(user_token, attrs) do
    user_token
    |> cast(attrs, [:user_id, :token, :name, :last_used_at, :revoked_at])
    |> validate_required([:user_id, :token])
    |> unique_constraint(:token)
  end

  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
