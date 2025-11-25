defmodule Mix.Tasks.Ecto.Drop do
  use Mix.Task

  @shortdoc "❌ Do not use directly - use 'mix db.reset' instead"

  @moduledoc """
  This is an override task to prevent accidental use of ecto.drop.

  ❌ DO NOT USE `mix ecto.drop` DIRECTLY

  Instead use the safe wrapper: `mix db.reset`

  Examples:
    - Reset projections:   mix db.reset --projections
    - Reset system:        mix db.reset --system
    - Reset events:        mix db.reset --events (DANGER!)
    - Reset everything:    mix db.reset --all (EXTREME DANGER!)

  See: mix db.reset
  """

  def run(_args) do
    Mix.raise("""
    ❌ ERROR: Do not use 'mix ecto.drop' directly!

    Use the safe wrapper instead: 'mix db.reset'

    Options:
      mix db.reset --projections  Reset projections only (SAFE)
      mix db.reset --system       Reset system schema (DANGER)
      mix db.reset --events       Reset events schema (EXTREME DANGER!)
      mix db.reset --all          Reset everything (EXTREME DANGER!)

    For more info: mix db.reset
    """)
  end
end
