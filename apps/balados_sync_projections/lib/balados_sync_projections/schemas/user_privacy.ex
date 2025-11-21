defmodule BaladosSyncProjections.Schemas.UserPrivacy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "users.user_privacy" do
    field :user_id, :string, primary_key: true
    field :rss_source_feed, :string, primary_key: true
    field :rss_source_item, :string, primary_key: true
    field :privacy, :string, default: "public"

    timestamps(type: :utc_datetime)
  end

  def changeset(privacy, attrs) do
    privacy
    |> cast(attrs, [:user_id, :rss_source_feed, :rss_source_item, :privacy])
    |> validate_required([:user_id, :privacy])
    |> validate_inclusion(:privacy, ["public", "anonymous", "private"])
  end
end
