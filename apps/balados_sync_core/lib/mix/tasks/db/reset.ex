defmodule Mix.Tasks.Db.Reset do
  use Mix.Task

  @shortdoc "Safely reset database schemas with validation"

  @moduledoc """
  Resets database schemas with required confirmation.

  Uses ecto.drop/create for Ecto repos and event_store.drop/create for EventStore.

  ## Options

  - `--system` - Reset only system schema (users, tokens)
  - `--events` - Reset only events schema (EventStore) - EXTREME DANGER
  - `--projections` - Reset only projections (public schema)
  - `--all` - Reset everything (system, events, projections)
  - `--migrate` - Run db.migrate after reset (can be combined with other options)

  If no option is provided, shows usage.

  All resets require confirmation by typing 'DELETE' or 'DELETE ALL'.

  ## Examples

      $ mix db.reset --system
      $ mix db.reset --projections
      $ mix db.reset --all
      $ mix db.reset --projections --migrate
      $ mix db.reset --system --migrate
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          system: :boolean,
          events: :boolean,
          projections: :boolean,
          all: :boolean,
          migrate: :boolean
        ]
      )

    case {opts[:system], opts[:events], opts[:projections], opts[:all]} do
      {nil, nil, nil, nil} ->
        print_usage()

      {true, nil, nil, nil} ->
        reset_system()
        maybe_migrate(opts[:migrate], "--system")

      {nil, true, nil, nil} ->
        reset_events()
        maybe_migrate(opts[:migrate], "--events")

      {nil, nil, true, nil} ->
        reset_projections()
        maybe_migrate(opts[:migrate], "--projections")

      {nil, nil, nil, true} ->
        reset_all()
        maybe_migrate(opts[:migrate], nil)

      _ ->
        Mix.raise("Only one of --system, --events, --projections, or --all can be specified")
    end
  end

  defp maybe_migrate(false, _repo_option), do: nil
  defp maybe_migrate(nil, _repo_option), do: nil

  defp maybe_migrate(true, repo_option) do
    Mix.shell().info("\nRunning migrations...")

    if repo_option do
      Mix.Tasks.Db.Migrate.run([repo_option])
    else
      Mix.Tasks.Db.Migrate.run([])
    end
  end

  defp print_usage do
    IO.puts("""
    Usage: mix db.reset [OPTION] [--migrate]

    Safely reset database schemas with validation.

    Options:
      --system       Reset only system schema (users, tokens)
      --events       Reset only events schema (EventStore) - EXTREME DANGER
      --projections  Reset only projections (public schema)
      --all          Reset everything (system, events, projections)
      --migrate      Run db.migrate after reset (optional)

    Examples:
      $ mix db.reset --system
      $ mix db.reset --projections
      $ mix db.reset --projections --migrate
      $ mix db.reset --all
    """)
  end

  defp reset_system do
    Mix.shell().info("""
    ⚠️  DANGER: You are about to delete all system data!
    This includes: users, API tokens, play tokens

    Events and projections will be preserved.
    """)

    case get_confirmation("Type 'DELETE' to confirm:") do
      :confirmed ->
        Mix.shell().info("Resetting system schema...")
        Mix.Tasks.Ecto.Drop.run(["--repo", "BaladosSyncProjections.SystemRepo"])
        Mix.Tasks.Ecto.Create.run(["--repo", "BaladosSyncProjections.SystemRepo"])
        Mix.shell().info("✅ System schema reset complete")

      :cancelled ->
        Mix.shell().info("❌ Reset cancelled")
    end
  end

  defp reset_events do
    Mix.shell().info("""
    ☢️  EXTREME DANGER: You are about to delete all events!

    ⚠️  EVENTS ARE YOUR SOURCE OF TRUTH AND CANNOT BE RECOVERED

    This operation:
    - Deletes the entire EventStore
    - Corrupts all projections
    - Makes the system unusable until events are replayed

    System data (users, tokens) will be preserved.
    """)

    case get_confirmation("Type 'DELETE ALL EVENTS' to confirm:") do
      :confirmed ->
        Mix.shell().info("Resetting EventStore...")
        Mix.Tasks.EventStore.Drop.run([])
        Mix.Tasks.EventStore.Create.run([])
        Mix.shell().info("✅ EventStore reset complete (EVENTS DELETED!)")

      :cancelled ->
        Mix.shell().info("❌ Reset cancelled")
    end
  end

  defp reset_projections do
    Mix.shell().info("""
    ✅ SAFE: You are about to reset projections only.

    This will:
    - Wipe public schema (trending, popularity data)
    - Reset projector positions
    - Trigger automatic rebuild from events

    System data and events will be preserved.
    """)

    case get_confirmation("Type 'DELETE' to confirm:") do
      :confirmed ->
        Mix.shell().info("Resetting projections schema...")
        Mix.Tasks.Ecto.Drop.run(["--repo", "BaladosSyncProjections.ProjectionsRepo"])
        Mix.Tasks.Ecto.Create.run(["--repo", "BaladosSyncProjections.ProjectionsRepo"])
        Mix.shell().info("✅ Projections reset complete")

      :cancelled ->
        Mix.shell().info("❌ Reset cancelled")
    end
  end

  defp reset_all do
    Mix.shell().info("""
    ☢️  EXTREME DANGER: You are about to delete EVERYTHING!

    This operation:
    - Deletes all system data (users, tokens)
    - Deletes all events (CANNOT BE RECOVERED!)
    - Deletes all projections

    After this, you must run migrations to recreate the schemas.
    """)

    case get_confirmation("Type 'DELETE ALL DATA' to confirm:") do
      :confirmed ->
        Mix.shell().info("Wiping all data...")
        Mix.Tasks.Ecto.Drop.run([])
        Mix.Tasks.EventStore.Drop.run([])
        Mix.Tasks.Ecto.Create.run([])
        Mix.Tasks.EventStore.Create.run([])
        Mix.shell().info("✅ All data deleted")

      :cancelled ->
        Mix.shell().info("❌ Reset cancelled")
    end
  end

  defp get_confirmation(prompt) do
    response = Mix.shell().prompt(prompt) |> String.trim()

    case response do
      "DELETE" -> :confirmed
      "DELETE ALL EVENTS" -> :confirmed
      "DELETE ALL DATA" -> :confirmed
      _ -> :cancelled
    end
  end
end
