defmodule BaladosSyncProjections.Repo.Migrations.AddPlaylistFields do
  use Ecto.Migration

  def change do
    # Add user_id to playlist_items for direct access
    alter table(:playlist_items, prefix: "users") do
      add :user_id, :string
      add :position, :integer
    end

    # Create unique index on (user_id, playlist_id, rss_source_feed, rss_source_item)
    create unique_index(:playlist_items,
      [:user_id, :playlist_id, :rss_source_feed, :rss_source_item],
      prefix: "users",
      name: "playlist_items_unique_idx"
    )

    # Create index for queries by user_id and playlist_id
    create index(:playlist_items,
      [:user_id, :playlist_id],
      prefix: "users",
      name: "playlist_items_user_playlist_idx"
    )
  end
end
