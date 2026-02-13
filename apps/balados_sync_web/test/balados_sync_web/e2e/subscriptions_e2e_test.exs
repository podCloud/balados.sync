defmodule BaladosSyncWeb.SubscriptionsE2ETest do
  @moduledoc """
  End-to-end tests for the subscriptions management flow.
  """

  use BaladosSyncWeb.E2ECase, async: false

  @moduletag :e2e

  describe "subscriptions page" do
    setup %{session: session} do
      %{email: email, password: password, user: user} = create_test_user()
      session = login(session, email, password)
      {:ok, session: session, user: user}
    end

    test "displays subscriptions page heading after login", %{session: session} do
      session
      |> visit("/subscriptions")
      |> wait_for_liveview()
      |> assert_has(Query.css("h1", text: "My Subscriptions"))
    end

    test "displays subscription count", %{session: session} do
      session
      |> visit("/subscriptions")
      |> wait_for_liveview()
      |> assert_has(Query.css("h1", text: "My Subscriptions"))
      |> assert_has(Query.text("subscriptions"))
    end
  end

  describe "add subscription form" do
    setup %{session: session} do
      %{email: email, password: password, user: user} = create_test_user()
      session = login(session, email, password)
      {:ok, session: session, user: user}
    end

    test "displays add subscription form with feed URL input", %{session: session} do
      session
      |> visit("/subscriptions/new")
      |> assert_has(Query.css("form"))
      |> assert_has(Query.text("Add New Subscription"))
      |> assert_has(Query.css("input#feed_url"))
    end
  end
end
