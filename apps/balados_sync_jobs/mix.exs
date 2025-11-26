defmodule BaladosSyncJobs.MixProject do
  use Mix.Project

  def project do
    [
      app: :balados_sync_jobs,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BaladosSyncJobs.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:quantum, "~> 3.5"},
      {:balados_sync_core, in_umbrella: true},
      {:balados_sync_projections, in_umbrella: true}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # Safety: block all direct ecto.* commands
      "ecto.drop": "ecto.disabled.drop",
      "ecto.reset": "ecto.disabled.reset",
      "ecto.migrate": "ecto.disabled.migrate",
      "ecto.create": "ecto.disabled.create"
    ]
  end
end
