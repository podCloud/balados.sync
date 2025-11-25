defmodule Mix.Tasks.SystemDb.Create do
  use Mix.Task

  @shortdoc "Create the system database with system schema"

  @moduledoc """
  Creates the system database and initializes the `system` schema prefix.

  This is equivalent to running `ecto.create --prefix system` on the projections repo.

  ## Example

      $ mix system_db.create
  """

  def run(args) do
    Mix.Task.run("ecto.create", args ++ ["--prefix", "system"])
  end
end
