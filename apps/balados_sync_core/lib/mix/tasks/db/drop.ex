defmodule Mix.Tasks.Db.Drop do
  use Mix.Task

  @shortdoc "Drop all databases (EXTREME DANGER)"

  @moduledoc """
  Drops all databases and schemas.

  ## EXTREME DANGER

  This operation is irreversible and will delete:
  - system schema: users and authentication tokens (NOT event-sourced, permanent loss)
  - events schema: EventStore (source of truth, permanent loss)
  - users schema: all projection tables (can be rebuilt from events)
  - public schema: all projection tables (can be rebuilt from events)

  Users and events are equally critical. Since users are not event-sourced,
  deleting them is as catastrophic as deleting events.

  ## Recovery

  After running this, you must:
  1. Run: mix db.create
  2. Run: mix db.init
  3. Create a new admin user via web interface

  ## Usage

      mix db.drop

  You will be prompted to confirm with the exact phrase.
  """

  def run(_args) do
    Mix.shell().info("☢️  WARNING: About to drop ALL databases")
    Mix.shell().info("")
    Mix.shell().info("This will permanently delete:")
    Mix.shell().info("  • system schema: all users and authentication tokens")
    Mix.shell().info("  • events schema: EventStore")
    Mix.shell().info("  • users/public schemas: all projections")
    Mix.shell().info("")
    Mix.shell().info("Users are NOT event-sourced and cannot be recovered.")
    Mix.shell().info("Events are the source of truth and cannot be recovered.")
    Mix.shell().info("")

    case get_confirmation() do
      :confirmed ->
        Mix.shell().info("Proceeding with database drop...")
        Process.sleep(2000)

        # Call the real ecto.drop directly (bypasses the CLI alias)
        # Use apply with dynamically constructed module name to avoid compile-time check
        module = String.to_atom("Elixir.Mix.Tasks.Ecto.Drop")
        apply(module, :run, [[]])

        Mix.shell().info("✓ All databases dropped")
        Mix.shell().info("")
        Mix.shell().info("Next steps:")
        Mix.shell().info("  1. mix db.create")
        Mix.shell().info("  2. mix db.init")
        Mix.shell().info("  3. Create a new admin user")

      :cancelled ->
        Mix.shell().info("Cancelled - all data preserved")
    end
  end

  defp get_confirmation do
    Mix.shell().info("Type the exact phrase to confirm:")
    Mix.shell().info("  DELETE ALL USERS AND EVENTS")
    Mix.shell().info("")

    case Mix.shell().prompt("Confirmation: ") |> String.trim() do
      "DELETE ALL USERS AND EVENTS" -> :confirmed
      _ -> :cancelled
    end
  end
end
