defmodule BaladosSyncCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BaladosSyncCore.SystemRepo,
      BaladosSyncCore.Dispatcher,
      {DNSCluster, query: Application.get_env(:balados_sync, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BaladosSyncCore.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: BaladosSyncCore.Finch}
      # Start a worker by calling: BaladosSyncCore.Worker.start_link(arg)
      # {BaladosSyncCore.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BaladosSyncCore.Supervisor)
  end
end
