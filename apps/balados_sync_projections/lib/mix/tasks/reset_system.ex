defmodule Mix.Tasks.ResetSystem do
  @shortdoc "Resets system tables (DANGER - requires confirmation)"

  @moduledoc """
  Resets all system tables (users, app_tokens, play_tokens).

  ⚠️  DANGER: This deletes all user accounts and authorization tokens!

  This task is intended for development/testing only.
  Requires explicit confirmation.

  ## Usage

      mix reset_system

  ## What gets deleted

  ### System Schema:
  - users (all user accounts and passwords)
  - app_tokens (all app authorizations)
  - play_tokens (all play gateway tokens)

  ### What is preserved:
  - All projections (can be rebuilt from events)
  - EventStore (all events remain)

  Note: If you want to reset EVERYTHING including projections,
  use `mix ecto.reset` instead.
  """

  use Mix.Task

  alias BaladosSyncProjections.Repo

  @system_tables [
    "users",
    "app_tokens",
    "play_tokens"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    # Show warning and request confirmation
    Mix.shell().error("")
    Mix.shell().error("⚠️  DANGER: You are about to delete all system data!")
    Mix.shell().error("")
    Mix.shell().error("This will permanently delete:")
    Mix.shell().error("  - All user accounts and passwords")
    Mix.shell().error("  - All app authorization tokens")
    Mix.shell().error("  - All play gateway tokens")
    Mix.shell().error("")
    Mix.shell().error("Projections and EventStore will be preserved.")
    Mix.shell().error("")

    confirmation =
      Mix.shell().prompt("Type 'DELETE SYSTEM DATA' to confirm, or anything else to cancel:")

    if String.trim(confirmation) == "DELETE SYSTEM DATA" do
      truncate_system_tables()

      Mix.shell().info("")
      Mix.shell().info("✓ System tables reset successfully!")
    else
      Mix.shell().info("")
      Mix.shell().info("Cancelled. No data was deleted.")
    end
  end

  defp truncate_system_tables do
    Mix.shell().info("")
    Mix.shell().info("Truncating system tables...")

    Repo.transaction(fn ->
      # Disable triggers and foreign key constraints temporarily
      Repo.query!("SET session_replication_role = replica")

      # Truncate system schema tables
      Enum.each(@system_tables, fn table ->
        Mix.shell().info("  - system.#{table}")
        Repo.query!("TRUNCATE TABLE system.#{table} CASCADE")
      end)

      # Re-enable constraints
      Repo.query!("SET session_replication_role = DEFAULT")
    end)
  end
end
