defmodule Mix.Tasks.Db.Migrate do
  use Mix.Task

  @shortdoc "Run all database migrations"

  @moduledoc """
  Runs migrations for all schemas in the correct order:
  1. System schema (users, app_tokens, play_tokens)
  2. Projection schemas (users, public subscriptions, events, etc.)

  ## Examples

      $ mix db.migrate
  """

  def run(args) do
    Mix.shell().info("Running system migrations...")
    Mix.Tasks.System.Migrate.run(args)

    Mix.shell().info("Running projections migrations...")
    Mix.Tasks.Projections.Migrate.run(args)

    Mix.shell().info("✓ All migrations completed successfully")
  end
end
