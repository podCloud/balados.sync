defmodule Mix.Tasks.Ecto.Disabled.Reset do
  use Mix.Task

  @shortdoc "❌ Do not use - use 'mix db.reset' instead"

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.reset' directly!

    Use the safe wrapper instead:

    - mix db.reset --projections  Reset projections only (SAFE)
    - mix db.reset --system       Reset system schema (DANGER)
    - mix db.reset --all          Reset everything (EXTREME DANGER!)

    For more info: mix db.reset
    """)
  end
end
