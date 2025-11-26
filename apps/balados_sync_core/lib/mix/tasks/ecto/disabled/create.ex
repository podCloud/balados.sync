defmodule Mix.Tasks.Ecto.Disabled.Create do
  use Mix.Task

  @shortdoc "❌ Do not use - use 'mix db.create' instead"

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.create' directly!

    Use the safe wrapper instead:

    - mix db.create               Create databases

    For more info: mix db.create
    """)
  end
end
