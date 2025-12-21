defmodule BaladosSyncProjections.ProjectionsRepo.Migrations.AddUniqueConstraintsForSync do
  use Ecto.Migration

  def change do
    # Unique constraint for playlists (id, user_id)
    # Note: id is already primary key, but we need a composite unique for upsert
    create unique_index(:playlists, [:id, :user_id], prefix: "users", name: :playlists_id_user_id_unique)

    # Unique constraint for playlist_items
    create unique_index(:playlist_items, [:playlist_id, :rss_source_feed, :rss_source_item, :user_id],
      prefix: "users",
      name: :playlist_items_composite_unique
    )

    # Unique constraint for subscriptions (user_id, rss_source_feed)
    create unique_index(:subscriptions, [:user_id, :rss_source_feed],
      prefix: "users",
      name: :subscriptions_user_feed_unique
    )

    # Unique constraint for play_statuses (user_id, rss_source_item)
    create unique_index(:play_statuses, [:user_id, :rss_source_item],
      prefix: "users",
      name: :play_statuses_user_item_unique
    )
  end
end
