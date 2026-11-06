defmodule BaladosSyncWeb.Rfc1123Test do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.Rfc1123

  describe "format/1" do
    test "formats a UTC datetime like Timex's {RFC1123} did" do
      assert Rfc1123.format(~U[2026-11-05 18:00:00Z]) == "Thu, 05 Nov 2026 18:00:00 +0000"
    end

    test "drops microseconds and zero-pads day, hour and minute" do
      assert Rfc1123.format(~U[2025-01-03 04:05:06.123456Z]) == "Fri, 03 Jan 2025 04:05:06 +0000"
    end

    test "shifts a non-UTC datetime to UTC before formatting" do
      {:ok, dt} = DateTime.from_naive(~N[2025-11-03 10:00:00], "Etc/UTC")
      plus_two = %{dt | utc_offset: 7200, time_zone: "Etc/GMT-2", zone_abbr: "+02"}
      assert Rfc1123.format(plus_two) == "Mon, 03 Nov 2025 08:00:00 +0000"
    end
  end

  describe "parse/1" do
    test "parses a numeric positive offset to UTC" do
      assert {:ok, dt} = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 +0530")
      assert DateTime.compare(dt, ~U[2025-11-03 04:30:00Z]) == :eq
    end

    test "parses a numeric negative offset to UTC" do
      assert {:ok, dt} = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 -0500")
      assert DateTime.compare(dt, ~U[2025-11-03 15:00:00Z]) == :eq
    end

    test "accepts GMT, UTC and Z as zero offset" do
      for zone <- ["GMT", "UTC", "Z", "+0000"] do
        assert {:ok, dt} = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 #{zone}")
        assert DateTime.compare(dt, ~U[2025-11-03 10:00:00Z]) == :eq
      end
    end

    test "accepts a single-digit day and a missing weekday" do
      assert {:ok, dt} = Rfc1123.parse("Mon, 3 Nov 2025 10:00:00 +0000")
      assert DateTime.compare(dt, ~U[2025-11-03 10:00:00Z]) == :eq
      assert {:ok, dt} = Rfc1123.parse("03 Nov 2025 10:00:00 +0000")
      assert DateTime.compare(dt, ~U[2025-11-03 10:00:00Z]) == :eq
    end

    test "accepts a full weekday name" do
      assert {:ok, dt} = Rfc1123.parse("Monday, 03 Nov 2025 10:00:00 +0000")
      assert DateTime.compare(dt, ~U[2025-11-03 10:00:00Z]) == :eq
    end

    test "accepts the RFC 822 North American zone names" do
      for {zone, expected} <- [
            {"EST", ~U[2025-11-03 15:00:00Z]},
            {"EDT", ~U[2025-11-03 14:00:00Z]},
            {"CST", ~U[2025-11-03 16:00:00Z]},
            {"CDT", ~U[2025-11-03 15:00:00Z]},
            {"MST", ~U[2025-11-03 17:00:00Z]},
            {"MDT", ~U[2025-11-03 16:00:00Z]},
            {"PST", ~U[2025-11-03 18:00:00Z]},
            {"PDT", ~U[2025-11-03 17:00:00Z]}
          ] do
        assert {:ok, dt} = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 #{zone}")
        assert DateTime.compare(dt, expected) == :eq, zone
      end
    end

    test "rejects signed or malformed numeric fields" do
      assert :error = Rfc1123.parse("Mon, +3 Nov 2025 10:00:00 +0000")
      assert :error = Rfc1123.parse("Mon, 03 Nov -2025 10:00:00 +0000")
      assert :error = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 +-100")
      assert :error = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 +0099")
      assert :error = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 CET")
      assert :error = Rfc1123.parse("Mon, 03 Nov 2025 10:00:00 +2400")
    end

    test "trims surrounding whitespace" do
      assert {:ok, _} = Rfc1123.parse("  Mon, 03 Nov 2025 10:00:00 +0000  ")
    end

    test "returns :error on garbage, impossible dates and nil" do
      assert :error = Rfc1123.parse("garbage")
      assert :error = Rfc1123.parse("Mon, 31 Feb 2025 10:00:00 +0000")
      assert :error = Rfc1123.parse("Mon, 03 Nov 2025 10:00 +0000")
      assert :error = Rfc1123.parse(nil)
    end

    test "round-trips format/1" do
      dt = ~U[2024-02-29 23:59:59Z]
      assert {:ok, parsed} = Rfc1123.parse(Rfc1123.format(dt))
      assert DateTime.compare(parsed, dt) == :eq
    end
  end
end
