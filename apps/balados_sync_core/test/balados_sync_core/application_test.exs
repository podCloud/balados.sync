defmodule BaladosSyncCore.ApplicationTest do
  # Mutates application env: not async.
  use ExUnit.Case, async: false

  alias BaladosSyncCore.Application, as: CoreApp

  setup do
    previous = Application.get_env(:balados_sync_core, :dns_cluster_query)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:balados_sync_core, :dns_cluster_query),
        else: Application.put_env(:balados_sync_core, :dns_cluster_query, previous)
    end)

    :ok
  end

  describe "dns_cluster_query/0" do
    test "uses the query config/runtime.exs sets from DNS_CLUSTER_QUERY" do
      Application.put_env(:balados_sync_core, :dns_cluster_query, "balados.internal")
      assert CoreApp.dns_cluster_query() == "balados.internal"
    end

    test "trims spaces around the configured query" do
      Application.put_env(:balados_sync_core, :dns_cluster_query, "  balados.internal \n")
      assert CoreApp.dns_cluster_query() == "balados.internal"
    end

    test "is :ignore when DNS_CLUSTER_QUERY is set but empty" do
      Application.put_env(:balados_sync_core, :dns_cluster_query, "")
      assert CoreApp.dns_cluster_query() == :ignore
      Application.put_env(:balados_sync_core, :dns_cluster_query, "  ")
      assert CoreApp.dns_cluster_query() == :ignore
    end

    test "is :ignore when no query is configured" do
      Application.delete_env(:balados_sync_core, :dns_cluster_query)
      assert CoreApp.dns_cluster_query() == :ignore
    end
  end
end
