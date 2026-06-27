defmodule Roundtable.LoadTestTest do
  use ExUnit.Case, async: false

  alias Roundtable.LoadTest

  describe "percentile/2" do
    test "nearest-rank over a sorted list" do
      sorted = Enum.to_list(1..100)
      assert LoadTest.percentile(sorted, 50) == 50
      assert LoadTest.percentile(sorted, 99) == 99
      assert LoadTest.percentile(sorted, 99.9) == 100
      assert LoadTest.percentile(sorted, 100) == 100
    end

    test "edges and empty" do
      assert LoadTest.percentile([], 99) == 0
      assert LoadTest.percentile([42], 50) == 42
      assert LoadTest.percentile([42], 99.9) == 42
    end
  end

  describe "run/2" do
    test "spawns N sessions, measures, and tears them down" do
      before = Roundtable.Telemetry.active_count()
      result = LoadTest.run(50)

      assert result.sessions == 50
      assert result.memory_per_session_kb > 0
      assert result.samples == 50

      %{p50: p50, p99: p99, p999: p999} = result.latency_us
      assert p50 >= 0 and p50 <= p99 and p99 <= p999
      assert is_integer(result.elapsed_ms)

      # cleaned up: active count returns to the prior baseline
      assert Roundtable.Telemetry.active_count() == before
    end
  end
end
