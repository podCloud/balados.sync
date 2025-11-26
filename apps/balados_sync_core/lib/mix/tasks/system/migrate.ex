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

    # Run migrations for SystemRepo using Ecto.Migrator
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    Ecto.Migrator.run(
      BaladosSyncProjections.SystemRepo,
      migrations_path(),
      :up,
      all: true
    )

    Mix.shell().info("✓ System migrations completed")
  end

  defp migrations_path do
    priv = :balados_sync_projections |> :code.priv_dir() |> to_string()
    Path.join(priv, "system_repo/migrations")
  end
end
