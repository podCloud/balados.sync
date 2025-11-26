defmodule Mix.Tasks.SystemDb.Migrate do
  use Mix.Task

  @shortdoc "Run system schema migrations"

  @moduledoc """
  Runs migrations for the `system` schema prefix.

  This bypasses the ecto.migrate safety wrapper and calls Ecto directly.

  ## Example

      $ mix system_db.migrate
  """

  def run(args) do
    # Call the real ecto.migrate directly (bypasses the CLI alias)
    module = String.to_atom("Elixir.Mix.Tasks.Ecto.Migrate")
    # Always add --prefix system for system_db.migrate
    apply(module, :run, [args ++ ["--prefix", "system"]])
  end
end
