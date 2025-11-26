defmodule BaladosSyncProjections.Repo.Migrations.CreateFunctions do
  use Ecto.Migration

  def up do
    # Fonction pour auto-update updated_at
    execute """
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $$ language 'plpgsql';
    """

    # Trigger pour users.subscriptions
    execute """
    CREATE TRIGGER update_subscriptions_updated_at 
    BEFORE UPDATE ON users.subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    """

    # Trigger pour users.playlists
    execute """
    CREATE TRIGGER update_playlists_updated_at 
    BEFORE UPDATE ON users.playlists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    """

    # Trigger pour users.playlist_items
    execute """
    CREATE TRIGGER update_playlist_items_updated_at 
    BEFORE UPDATE ON users.playlist_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    """

    # Fonction pour calculer si une subscription est active
    execute """
    CREATE OR REPLACE FUNCTION is_subscription_active(
      subscribed timestamp with time zone,
      unsubscribed timestamp with time zone
    ) RETURNS boolean AS $$
    BEGIN
      RETURN unsubscribed IS NULL OR subscribed > unsubscribed;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    # Vue matérialisée pour les podcasts trending (optionnel)
    execute """
    CREATE MATERIALIZED VIEW public.trending_podcasts AS
    SELECT
      rss_source_feed,
      feed_title,
      feed_author,
      feed_cover,
      score,
      score - score_previous as score_delta,
      plays,
      plays - plays_previous as plays_delta,
      likes,
      likes - likes_previous as likes_delta,
      plays_people,
      updated_at
    FROM public.podcast_popularity
    WHERE score - score_previous > 0
    ORDER BY (score - score_previous) DESC, score DESC
    LIMIT 100;
    """

    execute """
    CREATE UNIQUE INDEX trending_podcasts_feed_idx
    ON public.trending_podcasts (rss_source_feed);
    """
  end

  def down do
    execute "DROP MATERIALIZED VIEW IF EXISTS public.trending_podcasts"

    execute "DROP FUNCTION IF EXISTS is_subscription_active(timestamp with time zone, timestamp with time zone)"

    execute "DROP TRIGGER IF EXISTS update_playlist_items_updated_at ON users.playlist_items"
    execute "DROP TRIGGER IF EXISTS update_playlists_updated_at ON users.playlists"
    execute "DROP TRIGGER IF EXISTS update_subscriptions_updated_at ON users.subscriptions"
    execute "DROP FUNCTION IF EXISTS update_updated_at_column()"
  end
end
