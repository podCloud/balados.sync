defmodule BaladosSyncProjections.Schemas.Playlist do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "users"
  schema "playlists" do
    field :user_id, :string
    field :name, :string
    field :description, :string
    field :deleted_at, :utc_datetime

    # Virtual field for optimized item counting (avoids N+1 queries)
    field :items_count, :integer, virtual: true

    has_many :items, BaladosSyncProjections.Schemas.PlaylistItem

    timestamps(type: :utc_datetime)
  end

  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [:user_id, :name, :description])
    |> validate_required([:user_id, :name])
  end
end
