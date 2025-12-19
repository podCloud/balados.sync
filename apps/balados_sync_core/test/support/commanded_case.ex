defmodule BaladosSyncCore.CommandedCase do
  @moduledoc """
  Test case for tests that dispatch commands through the CQRS/Event Sourcing layer.

  This case template:
  - Resets the In-Memory EventStore before each test for isolation
  - Sets up Ecto sandboxes for SystemRepo and ProjectionsRepo
  - Supports async: true tests with proper isolation

  ## Usage

      defmodule MyTest do
        use BaladosSyncCore.CommandedCase, async: true

        test "dispatches command successfully" do
          user_id = Ecto.UUID.generate()
          # ... test that dispatches commands
        end
      end

  ## Important Notes

  - Always use `Ecto.UUID.generate()` for user_ids and other UUIDs
  - The EventStore is reset before each test, so events don't persist
  - Projections are isolated via Ecto sandbox
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias BaladosSyncCore.Dispatcher
      alias BaladosSyncCore.SystemRepo
      alias BaladosSyncProjections.ProjectionsRepo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import BaladosSyncCore.CommandedCase
    end
  end

  setup tags do
    # Reset the In-Memory EventStore before each test
    :ok = reset_event_store()

    # Setup Ecto sandboxes for database isolation
    setup_sandbox(tags)

    :ok
  end

  @doc """
  Resets the In-Memory EventStore to provide test isolation.
  """
  def reset_event_store do
    Commanded.EventStore.Adapters.InMemory.reset!(BaladosSyncCore.Dispatcher)
  end

  @doc """
  Sets up the Ecto sandboxes based on the test tags.

  This function ensures dependent applications are started and sets up
  sandboxes for both repos.
  """
  def setup_sandbox(tags) do
    # Ensure all dependent applications are started
    ensure_apps_started()

    repos = [BaladosSyncCore.SystemRepo, BaladosSyncProjections.ProjectionsRepo]

    # Use checkout mode for sync tests to avoid issues with stop_owner
    if tags[:async] do
      # For async tests, use start_owner with proper cleanup
      pids =
        for repo <- repos,
            repo_started?(repo) do
          Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: false)
        end

      on_exit(fn ->
        for pid <- pids do
          Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
        end
      end)
    else
      # For sync tests, use checkout mode which is simpler.
      # No explicit cleanup is needed because ExUnit's sandbox mode
      # automatically rolls back transactions at the end of each test.
      for repo <- repos, repo_started?(repo) do
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)
      end
    end
  end

  defp ensure_apps_started do
    # Start apps if not already running
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:balados_sync_core)
    Application.ensure_all_started(:balados_sync_projections)

    # Brief pause to allow Repo GenServers to fully initialize after application start.
    # This addresses a known race condition where Application.ensure_all_started/1 returns
    # before the Repo processes are ready to accept checkout requests. Without this,
    # tests may fail with "could not lookup Ecto repo" errors on slow CI systems.
    # The 10ms delay is minimal but sufficient for process registration to complete.
    Process.sleep(10)
  end

  defp repo_started?(repo) do
    case Process.whereis(repo) do
      nil -> false
      _pid -> true
    end
  end

  @doc """
  Waits for all projectors to process events.

  Useful when you need to verify projections after dispatching commands.
  The In-Memory EventStore processes events synchronously, but projectors
  may still need a moment to complete.
  """
  def wait_for_projections(timeout \\ 100) do
    Process.sleep(timeout)
  end
end
