defmodule BaladosSyncWeb.Helpers.PaginationTest do
  use ExUnit.Case, async: true

  import BaladosSyncWeb.Helpers.Pagination

  doctest BaladosSyncWeb.Helpers.Pagination

  describe "safe_parse_int/2" do
    test "handles zero" do
      assert safe_parse_int("0", 10) == 0
    end

    test "handles non-string input" do
      assert safe_parse_int(123, 10) == 10
      assert safe_parse_int(nil, 10) == 10
    end
  end
end
