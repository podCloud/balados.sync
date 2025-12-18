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
  """
  def setup_sandbox(tags) do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(BaladosSyncCore.SystemRepo,
        shared: not tags[:async]
      )

    pid2 =
      Ecto.Adapters.SQL.Sandbox.start_owner!(BaladosSyncProjections.ProjectionsRepo,
        shared: not tags[:async]
      )

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid2)
    end)
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
