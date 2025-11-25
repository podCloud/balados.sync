defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task

  @shortdoc "❌ Do not use directly - use 'mix db.migrate' or 'mix system_db.migrate' instead"

  @moduledoc """
  This is an override task to prevent accidental use of ecto.migrate.

  ❌ DO NOT USE `mix ecto.migrate` DIRECTLY

  Instead use the appropriate wrapper:
    - mix db.migrate       For migrating system schema (preferred)
    - mix system_db.migrate  For system schema migrations only
    - mix event_store.init -a balados_sync_core  For event store (one-time)

  See: mix db.migrate --help
  """

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.migrate' directly!

    Use the appropriate wrapper instead:

    For migrating the system schema:
      mix db.migrate
      (or: mix system_db.migrate for system schema only)

    For initializing event store (one-time):
      mix event_store.init -a balados_sync_core

    For more info: mix db.migrate
    """)
  end
end
