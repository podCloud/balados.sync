defmodule BaladosSyncProjections.ProjectionsRepo.Migrations.CreateUserLikes do
  use Ecto.Migration

  def up do
    create table(:user_likes, prefix: "users", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, :string, null: false
      add :rss_source_feed, :string, null: false
      add :rss_source_item, :string
      add :liked_at, :utc_datetime, null: false
      add :unliked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Unique constraint: one like per user per feed (podcast) or per user per feed+item (episode)
    # Using coalesce to handle NULL rss_source_item for podcast likes
    create unique_index(:user_likes, [:user_id, :rss_source_feed],
             prefix: "users",
             where: "rss_source_item IS NULL",
             name: "user_likes_user_feed_unique"
           )

    create unique_index(:user_likes, [:user_id, :rss_source_feed, :rss_source_item],
             prefix: "users",
             where: "rss_source_item IS NOT NULL",
             name: "user_likes_user_feed_item_unique"
           )

    create index(:user_likes, [:user_id], prefix: "users")
    create index(:user_likes, [:rss_source_feed], prefix: "users")

    # Partial index for active likes queries (GET /api/v1/likes filters on unliked_at IS NULL)
    create index(:user_likes, [:user_id],
             prefix: "users",
             where: "unliked_at IS NULL",
             name: "user_likes_user_active"
           )
  end

  def down do
    drop table(:user_likes, prefix: "users")
  end
end
