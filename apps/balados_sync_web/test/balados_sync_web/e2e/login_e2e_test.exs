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
      |> wait_for_liveview("form")
      |> assert_has(Query.text_field("Nom d'utilisateur"))
      |> assert_has(Query.text_field("Mot de passe"))
      |> assert_has(Query.button("Se connecter"))
    end

    test "shows error with invalid credentials", %{session: session} do
      session
      |> visit("/users/log_in")
      |> wait_for_liveview("form")
      |> fill_in(Query.text_field("Nom d'utilisateur"), with: "nonexistent@example.com")
      |> fill_in(Query.text_field("Mot de passe"), with: "wrongpassword")
      |> click(Query.button("Se connecter"))
      |> assert_has(
        Query.css(".text-rose-600", text: "Nom d'utilisateur ou mot de passe invalide")
      )
    end

    test "logs in with valid credentials", %{session: session} do
      %{email: email, password: password} = create_test_user()

      session
      |> visit("/users/log_in")
      |> wait_for_liveview("form")
      |> fill_in(Query.text_field("Nom d'utilisateur"), with: email)
      |> fill_in(Query.text_field("Mot de passe"), with: password)
      |> click(Query.button("Se connecter"))
      |> assert_has(Query.link("Log out"))
    end
  end

  describe "protected pages" do
    test "redirects unauthenticated users to login", %{session: session} do
      session
      |> visit("/subscriptions")
      |> assert_has(Query.css("form[action*='log_in']"))
    end
  end
end
