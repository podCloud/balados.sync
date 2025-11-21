defmodule BaladosSyncJobs.Application do
  use Application

  def start(_type, _args) do
    children = [
      BaladosSyncJobs.Scheduler
    ]

    opts = [strategy: :one_for_one, name: BaladosSyncJobs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
