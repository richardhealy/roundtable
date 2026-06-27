defmodule Roundtable.InitiativeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Roundtable.Initiative

  test "build/1 orders by roll desc, ties by combatant_id asc" do
    {:ok, init} = Initiative.build([{"bob", 12}, {"amy", 18}, {"cat", 12}])
    assert Enum.map(Initiative.to_list(init), & &1.combatant_id) == ["amy", "bob", "cat"]
    assert Initiative.current(init).combatant_id == "amy"
    assert Initiative.round(init) == 1
  end

  test "build/1 rejects empty and duplicate rosters" do
    assert Initiative.build([]) == {:error, :empty}
    assert Initiative.build([{"amy", 10}, {"amy", 9}]) == {:error, :duplicate_combatant}
  end

  test "advance/1 rotates and bumps round on wrap; rewind/1 inverts" do
    {:ok, i0} = Initiative.build([{"amy", 18}, {"bob", 12}])
    i1 = Initiative.advance(i0)
    assert Initiative.current(i1).combatant_id == "bob"
    assert Initiative.round(i1) == 1
    i2 = Initiative.advance(i1)
    assert Initiative.current(i2).combatant_id == "amy"
    assert Initiative.round(i2) == 2
    assert Initiative.current(Initiative.rewind(i2)).combatant_id == "bob"
    assert Initiative.round(Initiative.rewind(i2)) == 1
  end

  property "advancing `size` times returns to the start; multiset preserved" do
    check all entries <-
                uniq_list_of(tuple({string(:alphanumeric, min_length: 1), integer()}),
                  uniq_fun: &elem(&1, 0),
                  min_length: 1,
                  max_length: 12
                ) do
      {:ok, init} = Initiative.build(entries)
      size = length(entries)
      ids = fn i -> i |> Initiative.to_list() |> Enum.map(& &1.combatant_id) |> Enum.sort() end

      looped = Enum.reduce(1..size, init, fn _, acc -> Initiative.advance(acc) end)
      assert Initiative.current(looped).combatant_id == Initiative.current(init).combatant_id
      assert ids.(looped) == ids.(init)
    end
  end
end
