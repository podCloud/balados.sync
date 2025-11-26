defmodule Mix.Tasks.SystemDb.InitSchema do
  use Mix.Task

  @shortdoc "Create the system schema in the database"

  @moduledoc """
  Creates the `system` schema in the database if it doesn't exist.

  This must be run before system_db.migrate to ensure the schema exists.

  ## Example

      $ mix system_db.init_schema
  """

  def run(_args) do
    Mix.Task.run("app.start")

    repo = BaladosSyncProjections.SystemRepo

    try do
      # Create the system schema if it doesn't exist
      repo.query!("CREATE SCHEMA IF NOT EXISTS system")
      Mix.shell().info("✓ System schema initialized")
    rescue
      e ->
        Mix.shell().error("Error creating system schema: #{inspect(e)}")
    end
  end
end
