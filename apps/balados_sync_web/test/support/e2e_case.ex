defmodule BaladosSyncWeb.E2ECase do
  @moduledoc """
  Test case for End-to-End browser tests using Wallaby.

  E2E tests run against a real browser (headless Chrome by default) and test
  the full application stack including JavaScript and LiveView interactions.

  ## Setup Requirements

  1. ChromeDriver must be installed and in PATH
  2. Run E2E tests with: `mix test --include e2e`
  3. To see the browser: `WALLABY_HEADLESS=false mix test --include e2e`
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      alias Wallaby.Query

      import BaladosSyncWeb.E2ECase.Helpers
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BaladosSyncCore.SystemRepo)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BaladosSyncProjections.ProjectionsRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncCore.SystemRepo, {:shared, self()})
      Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncProjections.ProjectionsRepo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(BaladosSyncCore.SystemRepo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end

  defmodule Helpers do
    @moduledoc false

    alias Wallaby.Query
    alias BaladosSyncProjections.Schemas.User
    alias BaladosSyncCore.SystemRepo

    @doc "Create a test user and return credentials."
    def create_test_user(attrs \\ %{}) do
      email = attrs[:email] || "e2e-test-#{:rand.uniform(100_000)}@example.com"
      password = attrs[:password] || "TestPassword123!"

      user_attrs = %{
        email: email,
        hashed_password: Argon2.hash_pwd_salt(password),
        confirmed_at: DateTime.utc_now()
      }

      {:ok, user} =
        %User{}
        |> Ecto.Changeset.change(user_attrs)
        |> SystemRepo.insert()

      %{user: user, email: email, password: password}
    end

    @doc "Log in a user through the browser."
    def login(session, email, password) do
      session
      |> Wallaby.Browser.visit("/users/log_in")
      |> Wallaby.Browser.fill_in(Query.text_field("Email"), with: email)
      |> Wallaby.Browser.fill_in(Query.text_field("Password"), with: password)
      |> Wallaby.Browser.click(Query.button("Log in"))
    end

    @doc "Wait for LiveView to connect."
    def wait_for_liveview(session, timeout \\ 1000) do
      :timer.sleep(min(timeout, 1000))
      session
    end
  end
end
