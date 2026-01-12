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
      :timer.sleep(500)
      {:ok, session: session, user: user}
    end

    test "displays subscriptions page after login", %{session: session} do
      session
      |> visit("/subscriptions")
      |> wait_for_liveview()
      |> assert_has(Query.css("body"))
    end

    test "displays add subscription link", %{session: session} do
      session
      |> visit("/subscriptions")
      |> wait_for_liveview()
      |> assert_has(Query.link("Add subscription"))
    end
  end

  describe "add subscription form" do
    setup %{session: session} do
      %{email: email, password: password, user: user} = create_test_user()
      session = login(session, email, password)
      :timer.sleep(500)
      {:ok, session: session, user: user}
    end

    test "displays add subscription form", %{session: session} do
      session
      |> visit("/subscriptions/new")
      |> assert_has(Query.css("form"))
    end
  end

  describe "OPML import" do
    setup %{session: session} do
      %{email: email, password: password, user: user} = create_test_user()
      session = login(session, email, password)
      :timer.sleep(500)
      {:ok, session: session, user: user}
    end

    test "displays import OPML form", %{session: session} do
      session
      |> visit("/subscriptions/import")
      |> assert_has(Query.css("form"))
      |> assert_has(Query.css("input[type='file']"))
    end
  end
end
