defmodule Mix.Tasks.Db.Migrate do
  use Mix.Task

  @shortdoc "Run database migrations for specific repos or all"

  @moduledoc """
  Runs migrations for specified schemas or all.

  Migrations are run in order:
  1. System schema (users, app_tokens, play_tokens) - uses ecto.migrate
  2. Projections schemas (public subscriptions, etc.) - uses ecto.migrate
  3. EventStore schema (events) - uses event_store.init

  ## Options

  - `--system` - Run only system schema migrations
  - `--projections` - Run only projections migrations
  - `--events` - Run only EventStore migrations (event_store.init)

  If no option is provided, runs all migrations.

  ## Examples

      $ mix db.migrate
      $ mix db.migrate --system
      $ mix db.migrate --projections
      $ mix db.migrate --events
  """

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [system: :boolean, events: :boolean, projections: :boolean])

    case {opts[:system], opts[:events], opts[:projections]} do
      # No options: run all
      {nil, nil, nil} ->
        migrate_system(args)
        migrate_projections(args)
        migrate_events()
        Mix.shell().info("✓ All migrations completed successfully")

      # System only
      {true, nil, nil} ->
        migrate_system(args)
        Mix.shell().info("✓ System migrations completed successfully")

      # Projections only
      {nil, nil, true} ->
        migrate_projections(args)
        Mix.shell().info("✓ Projections migrations completed successfully")

      # Events only
      {nil, true, nil} ->
        migrate_events()
        Mix.shell().info("✓ EventStore migrations completed successfully")

      # Multiple options not allowed
      _ ->
        Mix.raise("Only one option (--system, --projections, or --events) can be specified at a time")
    end
  end

  defp migrate_system(args) do
    Mix.shell().info("Running system migrations...")
    Mix.Tasks.System.Migrate.run(args)
  end

  defp migrate_projections(args) do
    Mix.shell().info("Running projections migrations...")
    Mix.Tasks.Projections.Migrate.run(args)
  end

  defp migrate_events do
    Mix.shell().info("Initializing EventStore...")
    Mix.Tasks.EventStore.Init.run([])
  end
end
