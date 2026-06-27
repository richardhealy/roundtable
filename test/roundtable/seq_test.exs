defmodule Roundtable.Session.SeqTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Roundtable.Session.Seq

  test "new/0 starts at 0 and next/1 begins at 1" do
    ref = Seq.new()
    assert Seq.current(ref) == 0
    assert Seq.next(ref) == 1
    assert Seq.next(ref) == 2
    assert Seq.current(ref) == 2
  end

  property "concurrent next/1 yields exactly 1..total with no gaps or dups" do
    check all counts <- list_of(integer(1..50), min_length: 1, max_length: 20) do
      ref = Seq.new()
      total = Enum.sum(counts)

      results =
        counts
        |> Enum.map(fn n ->
          Task.async(fn -> for _ <- 1..n, do: Seq.next(ref) end)
        end)
        |> Task.await_many()
        |> List.flatten()

      assert length(results) == total
      assert Enum.sort(results) == Enum.to_list(1..total)
      assert Seq.current(ref) == total
    end
  end
end
