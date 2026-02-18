defmodule BaladosSyncWeb.LayoutHelpersTest do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.LayoutHelpers

  describe "current_path/1" do
    test "extracts path from conn assigns" do
      assigns = %{conn: %{request_path: "/subscriptions"}}
      assert LayoutHelpers.current_path(assigns) == "/subscriptions"
    end

    test "extracts path from socket assigns" do
      assigns = %{socket: %{private: %{live_path: "/subscriptions"}}}
      assert LayoutHelpers.current_path(assigns) == "/subscriptions"
    end

    test "returns / when neither conn nor socket is available" do
      assert LayoutHelpers.current_path(%{}) == "/"
    end

    test "returns / when socket has no live_path" do
      assigns = %{socket: %{private: %{}}}
      assert LayoutHelpers.current_path(assigns) == "/"
    end
  end

  describe "current_params/1" do
    test "extracts query params from conn assigns" do
      assigns = %{conn: %{query_params: %{"locale" => "fr", "page" => "2"}}}
      assert LayoutHelpers.current_params(assigns) == %{"locale" => "fr", "page" => "2"}
    end

    test "returns empty map for socket assigns" do
      assigns = %{socket: %{private: %{live_path: "/subscriptions"}}}
      assert LayoutHelpers.current_params(assigns) == %{}
    end

    test "returns empty map when no assigns" do
      assert LayoutHelpers.current_params(%{}) == %{}
    end
  end

  describe "nav_link_class/2" do
    test "returns active class when path matches prefix" do
      assert LayoutHelpers.nav_link_class("/subscriptions", "/subscriptions") ==
               "text-blue-600 border-b-2 border-blue-600"
    end

    test "returns active class for nested paths" do
      assert LayoutHelpers.nav_link_class("/subscriptions/123", "/subscriptions") ==
               "text-blue-600 border-b-2 border-blue-600"
    end

    test "returns inactive class when path does not match" do
      assert LayoutHelpers.nav_link_class("/dashboard", "/subscriptions") ==
               "hover:text-zinc-700"
    end

    test "returns inactive class for root path" do
      assert LayoutHelpers.nav_link_class("/", "/subscriptions") ==
               "hover:text-zinc-700"
    end
  end
end
