defmodule BaladosSyncWeb.AccessibilityTest do
  @moduledoc """
  Tests verifying ARIA attributes are present in rendered templates.
  Ensures accessibility improvements aren't accidentally removed.

  Component tests use rendered_to_string for fast, isolated verification.
  Page-level tests verify the full template renders with accessible structure.

  Note: JavaScript behavior (e.g. aria-expanded toggling in privacy-manager-page.ts)
  cannot be tested here. These require manual testing or E2E tests (Wallaby).
  Manual test: click edit button → verify aria-expanded="true", click cancel → "false".
  """
  use BaladosSyncWeb.ConnCase, async: true

  describe "page-level accessibility" do
    test "trending page renders with lang, alt text, and aria-hidden icons", %{conn: conn} do
      conn = get(conn, ~p"/trending/podcasts")
      html = html_response(conn, 200)

      assert html =~ ~r/<html lang="(en|fr)"/
      assert html =~ ~s(alt="Balados Sync")
      assert html =~ ~s(aria-hidden="true")
    end
  end

  describe "component accessibility - modal dialog semantics" do
    test "login_modal has role, aria-modal, and aria-labelledby" do
      html =
        render_component(:login_modal, %{
          id: "test-login-modal",
          login_url: "/users/log_in",
          register_url: "/users/register",
          inner_block: []
        })

      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(aria-labelledby="test-login-modal-title")
      assert html =~ ~s(id="test-login-modal-title")
    end

    test "subscribe_modal has role, aria-modal, and aria-labelledby" do
      html =
        render_component(:subscribe_modal, %{
          id: "test-subscribe-modal",
          subscribe_url: "/subscriptions",
          feed_url: "https://example.com/feed.xml",
          inner_block: []
        })

      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(aria-labelledby="test-subscribe-modal-title")
      assert html =~ ~s(id="test-subscribe-modal-title")
    end

    test "privacy_modal has role, aria-modal, aria-labelledby, and aria-describedby" do
      html =
        render_component(:privacy_modal, %{
          id: "test-privacy-modal",
          feed: "test-feed",
          context: "subscribe",
          inner_block: []
        })

      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(aria-labelledby="test-privacy-modal-title")
      assert html =~ ~s(aria-describedby="test-privacy-modal-desc")
      assert html =~ ~s(id="test-privacy-modal-title")
      assert html =~ ~s(id="test-privacy-modal-desc")
    end
  end

  describe "component accessibility - interactive elements" do
    test "modal close buttons have aria-label" do
      html =
        render_component(:login_modal, %{
          id: "test-modal",
          login_url: "/users/log_in",
          register_url: "/users/register",
          inner_block: []
        })

      assert html =~ ~s(aria-label="Close")
    end

    test "decorative SVGs in modals have aria-hidden" do
      html =
        render_component(:login_modal, %{
          id: "test-modal",
          login_url: "/users/log_in",
          register_url: "/users/register",
          inner_block: []
        })

      assert html =~ ~s(aria-hidden="true")
    end
  end

  defp render_component(component, assigns) do
    Phoenix.LiveViewTest.rendered_to_string(
      apply(BaladosSyncWeb.CoreComponents, component, [assigns])
    )
  end
end
