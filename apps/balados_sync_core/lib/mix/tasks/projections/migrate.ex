defmodule Mix.Tasks.Projections.Migrate do
  use Mix.Task

  @shortdoc "Run projections schema migrations"

  @moduledoc """
  Runs migrations for the projection schemas (users, public).

  ## Example

      $ mix projections.migrate
  """

  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    Ecto.Migrator.with_repo(
      BaladosSyncProjections.ProjectionsRepo,
      fn _repo ->
        Ecto.Migrator.run(
          BaladosSyncProjections.ProjectionsRepo,
          migrations_path(),
          :up,
          all: true
        )
      end,
      []
    )
  end

  defp migrations_path do
    priv = :balados_sync_projections |> :code.priv_dir() |> to_string()
    Path.join(priv, "projections_repo/migrations")
  end
end
