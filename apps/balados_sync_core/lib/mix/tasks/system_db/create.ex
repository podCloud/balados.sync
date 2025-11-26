defmodule Mix.Tasks.SystemDb.Create do
  use Mix.Task

  @shortdoc "Create the system database with system schema"

  @moduledoc """
  Creates the system database and initializes the `system` schema prefix.

  This bypasses the ecto.create safety wrapper and calls Ecto directly.

  ## Example

      $ mix system_db.create
  """

  def run(args) do
    # Call the real ecto.create directly (bypasses the CLI alias)
    module = String.to_atom("Elixir.Mix.Tasks.Ecto.Create")
    apply(module, :run, [args])
  end
end
