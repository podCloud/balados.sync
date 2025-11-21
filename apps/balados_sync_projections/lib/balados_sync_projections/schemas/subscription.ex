defmodule BaladosSyncProjections.Schemas.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users.subscriptions" do
    field :user_id, :string
    field :rss_source_feed, :string
    field :rss_source_id, :string
    field :rss_feed_title, :string
    field :subscribed_at, :utc_datetime
    field :unsubscribed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_id,
      :rss_source_feed,
      :rss_source_id,
      :rss_feed_title,
      :subscribed_at,
      :unsubscribed_at
    ])
    |> validate_required([:user_id, :rss_source_feed])
  end
end
