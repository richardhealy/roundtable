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
end
