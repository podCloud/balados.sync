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
    # Check if ChromeDriver is available before running E2E tests
    case System.find_executable("chromedriver") do
      nil ->
        raise """
        ChromeDriver not found in PATH. E2E tests require ChromeDriver.

        Install ChromeDriver:
          Arch Linux: sudo pacman -S chromium
          macOS:      brew install chromedriver
          Ubuntu:     sudo apt install chromium-chromedriver

        Then run: mix test --include e2e
        """

      _path ->
        :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BaladosSyncCore.SystemRepo)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BaladosSyncProjections.ProjectionsRepo)

    # Defense-in-depth DB sandbox strategy:
    # 1. Shared mode: allows any process (LiveView, controllers) to use the test connection
    # 2. Metadata-based ownership (via Phoenix.Ecto.SQL.Sandbox plug in endpoint.ex):
    #    Wallaby passes sandbox metadata in browser requests, allowing the endpoint
    #    to associate HTTP requests with the test process's DB connection.
    # Both are used together for reliability - shared mode covers server-side processes
    # while metadata covers browser-initiated HTTP requests.
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
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, user} =
        %User{}
        |> Ecto.Changeset.change(user_attrs)
        |> SystemRepo.insert()

      %{user: user, email: email, password: password}
    end

    @doc "Log in a user through the browser and wait for navigation to complete."
    def login(session, email, password) do
      session
      |> Wallaby.Browser.visit("/users/log_in")
      |> Wallaby.Browser.fill_in(Query.text_field("Nom d'utilisateur"), with: email)
      |> Wallaby.Browser.fill_in(Query.text_field("Mot de passe"), with: password)
      |> Wallaby.Browser.click(Query.button("Se connecter"))
      |> Wallaby.Browser.assert_has(Query.link("Log out"))
    end

    @doc """
    Wait for LiveView to mount and connect by asserting on a visible element.

    Instead of using an arbitrary sleep, this relies on Wallaby's built-in
    retry/wait mechanism through `assert_has`. Wallaby will poll the DOM
    until the element appears or the timeout is reached.

    The `selector` argument defaults to `"main"` which is present in the app
    layout once the page has rendered. Pass a more specific CSS selector to
    wait for a particular LiveView element.
    """
    def wait_for_liveview(session, selector \\ "main") do
      Wallaby.Browser.assert_has(session, Query.css(selector))
      session
    end
  end
end
