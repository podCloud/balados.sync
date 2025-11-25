defmodule Mix.Tasks.SystemDb.Migrate do
  use Mix.Task

  @shortdoc "Run system schema migrations"

  @moduledoc """
  Runs migrations for the `system` schema prefix.

  This is equivalent to running `ecto.migrate --prefix system` on the projections repo.

  ## Example

      $ mix system_db.migrate
  """

  def run(args) do
    Mix.Task.run("ecto.migrate", args ++ ["--prefix", "system"])
  end
end
