defmodule BaladosSyncProjections.Repo.Migrations.CreateSystemAndRenameSite do
  use Ecto.Migration

  def up do
    # Créer nouveau schéma system pour données permanentes (non event-sourced)
    execute "CREATE SCHEMA IF NOT EXISTS system"

    # Déplacer les tables de 'site' vers le schéma 'public' existant
    execute "ALTER TABLE site.podcast_popularity SET SCHEMA public"
    execute "ALTER TABLE site.episode_popularity SET SCHEMA public"
    execute "ALTER TABLE site.public_events SET SCHEMA public"

    # Supprimer le schéma 'site' et ses dépendances restantes (vues, etc.)
    execute "DROP SCHEMA site CASCADE"
  end

  def down do
    # Recréer le schéma site
    execute "CREATE SCHEMA site"

    # Déplacer les tables de 'public' vers 'site'
    execute "ALTER TABLE public.podcast_popularity SET SCHEMA site"
    execute "ALTER TABLE public.episode_popularity SET SCHEMA site"
    execute "ALTER TABLE public.public_events SET SCHEMA site"

    # Supprimer schéma system
    execute "DROP SCHEMA IF EXISTS system CASCADE"
  end
end
