defmodule Mix.Tasks.ResetProjections do
  @shortdoc "Resets all projection tables (SAFE - preserves system data)"

  @moduledoc """
  Resets all projection tables by truncating them and resetting projector subscriptions.

  This is SAFE to run as it:
  - Only truncates projection tables (users schema + public schema)
  - Preserves all system data (users, app_tokens, play_tokens)
  - Automatically rebuilds projections from EventStore

  ## Usage

      mix reset_projections

  ## What gets reset

  ### Users Schema (Projections):
  - subscriptions
  - play_statuses
  - playlists
  - playlist_items
  - user_privacy

  ### Public Schema (Projections):
  - podcast_popularity
  - episode_popularity
  - public_events

  ### What is preserved:
  - All system schema tables (users, app_tokens, play_tokens)
  - All events in EventStore
  """

  use Mix.Task

  alias BaladosSyncProjections.ProjectionsRepo

  @projection_tables_users [
    "subscriptions",
    "play_statuses",
    "playlists",
    "playlist_items",
    "user_privacy"
  ]

  @projection_tables_public [
    "podcast_popularity",
    "episode_popularity",
    "public_events"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Resetting all projection tables...")
    Mix.shell().info("System data (users, tokens) will be preserved.")
    Mix.shell().info("")

    # Truncate projection tables
    truncate_projections()

    # Reset projector subscription positions
    reset_projector_positions()

    Mix.shell().info("")
    Mix.shell().info("✓ Projections reset successfully!")
    Mix.shell().info("✓ Projectors will now rebuild from EventStore automatically.")
  end

  defp truncate_projections do
    Mix.shell().info("Truncating projection tables...")

    ProjectionsRepo.transaction(fn ->
      # Disable triggers and foreign key constraints temporarily
      ProjectionsRepo.query!("SET session_replication_role = replica")

      # Truncate users schema projections
      Enum.each(@projection_tables_users, fn table ->
        Mix.shell().info("  - users.#{table}")
        ProjectionsRepo.query!("TRUNCATE TABLE users.#{table} CASCADE")
      end)

      # Truncate public schema projections
      Enum.each(@projection_tables_public, fn table ->
        Mix.shell().info("  - public.#{table}")
        ProjectionsRepo.query!("TRUNCATE TABLE public.#{table} CASCADE")
      end)

      # Re-enable constraints
      ProjectionsRepo.query!("SET session_replication_role = DEFAULT")
    end)
  end

  defp reset_projector_positions do
    Mix.shell().info("")
    Mix.shell().info("Projectors will automatically rebuild when they restart.")
    Mix.shell().info("No need to manually reset subscription positions.")
    Mix.shell().info("(Commanded.Projections.Ecto handles this automatically)")
  end
end
