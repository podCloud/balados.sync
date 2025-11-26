defmodule Mix.Tasks.System.Migrate do
  use Mix.Task

  @shortdoc "Run system schema migrations"

  @moduledoc """
  Runs migrations for the `system` schema (users, app_tokens, play_tokens).

  ## Example

      $ mix system.migrate
  """

  def run(args) do
    # Initialize system schema first
    Mix.Tasks.SystemDb.InitSchema.run(args)

    # Run migrations for SystemRepo
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    module = String.to_atom("Elixir.Ecto.Cli")

    Ecto.Migrator.run(
      BaladosSyncProjections.SystemRepo,
      migrations_path(BaladosSyncProjections.SystemRepo),
      :up,
      all: true
    )
  end

  defp migrations_path(repo) do
    priv = :balados_sync_projections |> :code.priv_dir() |> to_string()
    Path.join(priv, "system_repo/migrations")
  end
end
