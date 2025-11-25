defmodule Mix.Tasks.Ecto.ResetConfirm do
  @shortdoc "Resets database with confirmation (DANGER)"

  @moduledoc """
  Wrapper for `mix ecto.reset` that requires explicit confirmation.

  ⚠️  DANGER: This deletes EVERYTHING in the database!

  This is a destructive operation that will delete:
  - All user accounts and passwords (system schema)
  - All app authorization tokens (system schema)
  - All projections (can be rebuilt from events)
  - All EventStore events (CANNOT be recovered!)

  ## Usage

      mix ecto.reset_confirm

  Or bypass confirmation (use with caution):

      mix ecto.reset!

  ## Safer alternatives

  - `mix reset_projections` - Only resets projections (SAFE)
  - `mix reset_system` - Only resets system tables (with confirmation)
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Show warning and request confirmation
    Mix.shell().error("")
    Mix.shell().error("⚠️  EXTREME DANGER: You are about to delete ALL DATA!")
    Mix.shell().error("")
    Mix.shell().error("This will permanently delete:")
    Mix.shell().error("  ❌ All user accounts and passwords")
    Mix.shell().error("  ❌ All app authorization tokens")
    Mix.shell().error("  ❌ All projections (subscriptions, play statuses, playlists, etc.)")
    Mix.shell().error("  ❌ ALL EventStore events (CANNOT BE RECOVERED!)")
    Mix.shell().error("")
    Mix.shell().error("Safer alternatives:")
    Mix.shell().error("  ✓ mix reset_projections  - Only resets projections (SAFE)")
    Mix.shell().error("  ✓ mix reset_system        - Only resets system data")
    Mix.shell().error("")

    confirmation =
      Mix.shell().prompt("Type 'DELETE ALL DATA' to confirm, or anything else to cancel:")

    if String.trim(confirmation) == "DELETE ALL DATA" do
      Mix.shell().info("")
      Mix.shell().info("Proceeding with database reset...")

      # Run the actual ecto.reset tasks
      Mix.Task.run("ecto.drop", args)
      Mix.Task.run("ecto.setup", args)

      Mix.shell().info("")
      Mix.shell().info("✓ Database reset complete!")
    else
      Mix.shell().info("")
      Mix.shell().info("Cancelled. No data was deleted.")
      Mix.shell().info("Consider using 'mix reset_projections' instead.")
    end
  end
end
