defmodule Mix.Tasks.Db.Migrate do
  use Mix.Task

  @shortdoc "Run all database migrations"

  @moduledoc """
  Runs migrations for all schemas (system, users, public).

  This ensures the system schema is initialized first, then runs all migrations.

  ## Example

      $ mix db.migrate
  """

  def run(args) do
    # First initialize the system schema
    Mix.Tasks.SystemDb.InitSchema.run(args)

    # Then run all migrations (without prefix, so they apply to all schemas)
    module = String.to_atom("Elixir.Mix.Tasks.Ecto.Migrate")
    apply(module, :run, [args])
  end
end
