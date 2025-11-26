defmodule Mix.Tasks.Projections.Migrate do
  use Mix.Task

  @shortdoc "Run projections schema migrations"

  @moduledoc """
  Runs migrations for the projection schemas (users, public).

  ## Example

      $ mix projections.migrate
  """

  def run(args) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    Ecto.Migrator.run(
      BaladosSyncProjections.ProjectionsRepo,
      migrations_path(BaladosSyncProjections.ProjectionsRepo),
      :up,
      all: true
    )
  end

  defp migrations_path(repo) do
    priv = :balados_sync_projections |> :code.priv_dir() |> to_string()
    Path.join(priv, "projections_repo/migrations")
  end
end
