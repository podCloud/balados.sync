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

  This function gracefully handles cases where repos may not be started
  (e.g., when running balados_sync_core tests in isolation).
  """
  def setup_sandbox(tags) do
    pids =
      for repo <- [BaladosSyncCore.SystemRepo, BaladosSyncProjections.ProjectionsRepo],
          repo_started?(repo) do
        Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: not tags[:async])
      end

    on_exit(fn ->
      for pid <- pids do
        Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
      end
    end)
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
