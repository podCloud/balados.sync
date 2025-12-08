defmodule BaladosSyncWeb.PlayTokenTest do
  use ExUnit.Case

  alias BaladosSyncProjections.Schemas.PlayToken

  describe "expired?/1" do
    test "returns false when expires_at is nil" do
      token = %PlayToken{expires_at: nil}
      refute PlayToken.expired?(token)
    end

    test "returns false when expiration is in the future" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      token = %PlayToken{expires_at: future_time}
      refute PlayToken.expired?(token)
    end

    test "returns true when expiration is in the past" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      token = %PlayToken{expires_at: past_time}
      assert PlayToken.expired?(token)
    end

    test "returns false when expiration is at or slightly after now (boundary)" do
      # Expiration exactly at now or in the future should not be expired
      future_time = DateTime.add(DateTime.utc_now(), 1, :second)
      token = %PlayToken{expires_at: future_time}
      refute PlayToken.expired?(token)
    end
  end

  describe "calculate_expiration/1" do
    test "calculates expiration 365 days from now by default" do
      result = PlayToken.calculate_expiration()
      expected = DateTime.utc_now() |> DateTime.add(365 * 86400, :second)

      # Allow 2 second tolerance for test execution time
      time_diff = DateTime.diff(result, expected)
      assert time_diff >= -2 and time_diff <= 2
    end

    test "calculates expiration N days from now" do
      days = 30
      result = PlayToken.calculate_expiration(days)
      expected = DateTime.utc_now() |> DateTime.add(days * 86400, :second)

      # Allow 2 second tolerance for test execution time
      time_diff = DateTime.diff(result, expected)
      assert time_diff >= -2 and time_diff <= 2
    end

    test "returns truncated to seconds" do
      result = PlayToken.calculate_expiration(1)
      assert result.microsecond == {0, 0}
    end

    test "raises on negative days" do
      assert_raise FunctionClauseError, fn ->
        PlayToken.calculate_expiration(-1)
      end
    end

    test "raises on zero days" do
      assert_raise FunctionClauseError, fn ->
        PlayToken.calculate_expiration(0)
      end
    end
  end
end
