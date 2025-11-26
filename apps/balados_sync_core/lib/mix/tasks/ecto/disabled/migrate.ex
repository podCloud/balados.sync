defmodule Mix.Tasks.Ecto.Disabled.Migrate do
  use Mix.Task

  @shortdoc "❌ Do not use - use 'mix db.migrate' instead"

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.migrate' directly!

    Use the safe wrapper instead:

    - mix db.migrate              Migrate database schema

    For more info: mix db.migrate
    """)
  end
end
