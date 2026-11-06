defmodule BaladosSyncWeb.CoreComponentsInputTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BaladosSyncWeb.CoreComponents

  # LiveView 1.0 removed phx-feedback-for: errors are hidden until the field
  # has been used, which the form params tell (Phoenix.Component.used_input?/1).
  defp render_input(params) do
    form = to_form(params, as: :playlist, errors: [name: {"zz custom failure", []}])
    render_component(&CoreComponents.input/1, field: form[:name], label: "Name")
  end

  test "hides the error of a field the user has not touched yet" do
    html = render_input(%{"_unused_name" => "", "name" => ""})
    refute html =~ "zz custom failure"
    refute html =~ "phx-feedback-for"
  end

  test "shows the error once the field has been used" do
    html = render_input(%{"name" => ""})
    assert html =~ "zz custom failure"
  end
end
