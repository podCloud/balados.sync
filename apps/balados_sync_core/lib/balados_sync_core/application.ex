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
      {DNSCluster, query: dns_cluster_query()},
      {Phoenix.PubSub, name: BaladosSyncCore.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: BaladosSyncCore.Finch}
      # Start a worker by calling: BaladosSyncCore.Worker.start_link(arg)
      # {BaladosSyncCore.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BaladosSyncCore.Supervisor)
  end

  @doc """
  DNS query used by `DNSCluster` for node discovery, set by `config/runtime.exs`
  from `DNS_CLUSTER_QUERY`; `:ignore` (no clustering) when unset or empty.
  Clustering also needs Erlang distribution with long names
  (`RELEASE_DISTRIBUTION=name`, `RELEASE_NODE=balados_sync@<ip-or-fqdn>`);
  without it DNSCluster only logs a warning.
  """
  @spec dns_cluster_query() :: String.t() | :ignore
  def dns_cluster_query do
    case Application.get_env(:balados_sync_core, :dns_cluster_query) do
      query when query in [nil, ""] -> :ignore
      query -> query
    end
  end
end
