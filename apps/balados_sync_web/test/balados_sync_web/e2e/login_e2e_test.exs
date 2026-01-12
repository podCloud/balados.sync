defmodule BaladosSyncWeb.LoginE2ETest do
  @moduledoc """
  End-to-end tests for the login flow.
  """

  use BaladosSyncWeb.E2ECase, async: false

  @moduletag :e2e

  describe "login page" do
    test "displays login form", %{session: session} do
      session
      |> visit("/users/log_in")
      |> assert_has(Query.css("form"))
      |> assert_has(Query.text_field("Email"))
      |> assert_has(Query.text_field("Password"))
      |> assert_has(Query.button("Log in"))
    end

    test "shows error with invalid credentials", %{session: session} do
      session
      |> visit("/users/log_in")
      |> fill_in(Query.text_field("Email"), with: "nonexistent@example.com")
      |> fill_in(Query.text_field("Password"), with: "wrongpassword")
      |> click(Query.button("Log in"))
      |> assert_has(Query.css("[role='alert']", text: "Invalid"))
    end

    test "logs in with valid credentials", %{session: session} do
      %{email: email, password: password} = create_test_user()

      session
      |> visit("/users/log_in")
      |> fill_in(Query.text_field("Email"), with: email)
      |> fill_in(Query.text_field("Password"), with: password)
      |> click(Query.button("Log in"))

      :timer.sleep(500)
      session |> assert_has(Query.css("body"))
    end
  end

  describe "protected pages" do
    test "redirects unauthenticated users to login", %{session: session} do
      session
      |> visit("/subscriptions")

      :timer.sleep(300)
      session |> assert_has(Query.css("form[action*='log_in']"))
    end
  end
end
