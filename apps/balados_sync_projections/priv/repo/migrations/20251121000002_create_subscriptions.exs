defmodule BaladosSyncProjections.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false, prefix: "users") do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :rss_source_feed, :text, null: false
      add :rss_source_id, :text
      add :rss_feed_title, :text
      add :subscribed_at, :utc_datetime
      add :unsubscribed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:user_id, :rss_source_feed], prefix: "users")
    create index(:subscriptions, [:user_id], prefix: "users")
    create index(:subscriptions, [:rss_source_feed], prefix: "users")

    # Index pour trouver les subscriptions actives
    create index(:subscriptions, [:user_id, :subscribed_at, :unsubscribed_at],
             prefix: "users",
             name: :subscriptions_active_idx,
             where: "unsubscribed_at IS NULL OR subscribed_at > unsubscribed_at"
           )
  end
end
