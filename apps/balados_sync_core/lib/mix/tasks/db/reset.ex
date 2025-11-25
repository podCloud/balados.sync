defmodule Mix.Tasks.Db.Reset do
  use Mix.Task

  @shortdoc "Safely reset database schemas with validation"

  @moduledoc """
  Resets database schemas with required confirmation.

  ## Options

  - `--system` - Reset only system schema (users, tokens)
  - `--events` - Reset only events schema (EventStore) - EXTREME DANGER
  - `--projections` - Reset only projections (public schema)
  - `--all` - Reset everything (system, events, projections)

  If no option is provided, shows usage.

  All resets require confirmation by typing 'DELETE' or 'DELETE ALL'.

  ## Examples

      $ mix db.reset --system
      $ mix db.reset --projections
      $ mix db.reset --all
  """

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [system: :boolean, events: :boolean, projections: :boolean, all: :boolean])

    case {opts[:system], opts[:events], opts[:projections], opts[:all]} do
      {nil, nil, nil, nil} ->
        print_usage()

      {true, nil, nil, nil} ->
        reset_system()

      {nil, true, nil, nil} ->
        reset_events()

      {nil, nil, true, nil} ->
        reset_projections()

      {nil, nil, nil, true} ->
        reset_all()

      _ ->
        Mix.raise("Only one option can be specified at a time")
    end
  end

  defp print_usage do
    IO.puts("""
    Usage: mix db.reset [OPTION]

    Safely reset database schemas with validation.

    Options:
      --system       Reset only system schema (users, tokens)
      --events       Reset only events schema (EventStore) - EXTREME DANGER
      --projections  Reset only projections (public schema)
      --all          Reset everything (system, events, projections)

    Examples:
      $ mix db.reset --system
      $ mix db.reset --projections
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
        Mix.Task.run("ecto.reset", ["--prefix", "system"])
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
        Mix.shell().info("Resetting events schema...")
        # Reset event store via Ecto
        Mix.Task.run("ecto.reset", ["--prefix", "events"])
        Mix.shell().info("✅ Events schema reset complete (EVENTS DELETED!)")
        Mix.shell().info("⚠️  You must replay events or restore from backup")

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
        Mix.Task.run("ecto.reset", ["--prefix", "public"])
        Mix.shell().info("✅ Projections reset complete - rebuilding from events...")

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

    After this, you must:
    1. Run: mix event_store.init -a balados_sync_core
    2. Run: mix db.init
    3. Create a new admin user via web interface
    """)

    case get_confirmation("Type 'DELETE ALL DATA' to confirm:") do
      :confirmed ->
        Mix.shell().info("Wiping all data...")
        Mix.Task.run("ecto.reset", [])
        Mix.shell().info("✅ All data deleted")
        Mix.shell().info("⚠️  You must now run:")
        Mix.shell().info("   1. mix event_store.init -a balados_sync_core")
        Mix.shell().info("   2. mix db.init")

      :cancelled ->
        Mix.shell().info("❌ Reset cancelled")
    end
  end

  defp get_confirmation(prompt) do
    case Mix.shell().prompt(prompt) do
      "DELETE" -> :confirmed
      "DELETE ALL EVENTS" -> :confirmed
      "DELETE ALL DATA" -> :confirmed
      _ -> :cancelled
    end
  end
end
