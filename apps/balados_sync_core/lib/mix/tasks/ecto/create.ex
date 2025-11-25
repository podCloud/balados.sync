defmodule Mix.Tasks.Ecto.Create do
  use Mix.Task

  @shortdoc "❌ Do not use directly - use 'mix db.create' or 'mix system_db.create' instead"

  @moduledoc """
  This is an override task to prevent accidental use of ecto.create.

  ❌ DO NOT USE `mix ecto.create` DIRECTLY

  Instead use the appropriate wrapper:
    - mix db.create       Creates system schema + event store (preferred)
    - mix system_db.create  For system schema only

  See: mix db.create --help
  """

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.create' directly!

    Use the appropriate wrapper instead:

    For full database initialization (recommended):
      mix db.create

    For system schema only:
      mix system_db.create

    For more info: mix db.create
    """)
  end
end
