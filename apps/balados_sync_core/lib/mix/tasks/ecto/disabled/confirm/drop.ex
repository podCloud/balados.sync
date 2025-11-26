defmodule Mix.Tasks.Ecto.Confirm.Drop do
  use Mix.Task

  @shortdoc "❌ Do not use - use 'mix db.drop' instead"

  @moduledoc """
  Safety wrapper that prevents direct use of ecto.drop.

  Use 'mix db.drop' instead for a safe database drop with confirmation.
  """

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.drop' directly!

    Use the safe wrapper instead:

    - mix db.reset --projections  Reset projections only (SAFE)
    - mix db.reset --system       Reset system schema (DANGER)
    - mix db.reset --events       Reset events schema (EXTREME DANGER!)
    - mix db.reset --all          Reset everything (EXTREME DANGER!)

    Or for dropping ALL databases:
    - mix db.drop                 Drop all databases (EXTREME DANGER!)

    For more info: mix db.reset or mix db.drop
    """)
  end
end
