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

  test "build/1 rejects a roll that is not an integer instead of raising" do
    for bad <- ["18", nil, 18.5, %{}, [18]] do
      assert Initiative.build([{"amy", 18}, {"bob", bad}]) == {:error, :invalid_roll}
    end
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

  test "first_turn?/1 holds only for round 1 with the leader up" do
    {:ok, i0} = Initiative.build([{"amy", 18}, {"bob", 12}])
    assert Initiative.first_turn?(i0)
    assert Initiative.first_turn?(Initiative.restore(Initiative.to_list(i0), 1))
    refute Initiative.first_turn?(Initiative.advance(i0))
    # amy is up again, but in round 2
    refute Initiative.first_turn?(i0 |> Initiative.advance() |> Initiative.advance())
  end

  test "rewind/1 on the very first turn leaves the ring as it is" do
    {:ok, i0} = Initiative.build([{"amy", 18}, {"bob", 12}, {"cat", 5}])
    assert Initiative.rewind(i0) == i0

    # no full round has passed, so bob's turn is still round 1
    i1 = i0 |> Initiative.rewind() |> Initiative.advance()
    assert Initiative.current(i1).combatant_id == "bob"
    assert Initiative.round(i1) == 1
  end

  test "restore/2 round-trips a snapshot, preserving rotation and round" do
    {:ok, i0} = Initiative.build([{"amy", 18}, {"bob", 12}, {"cat", 5}])
    advanced = i0 |> Initiative.advance() |> Initiative.advance()
    snap_order = Initiative.to_list(advanced)
    restored = Initiative.restore(snap_order, Initiative.round(advanced))
    assert Initiative.to_list(restored) == snap_order

    assert Initiative.current(restored).combatant_id ==
             Initiative.current(advanced).combatant_id

    assert Initiative.round(restored) == Initiative.round(advanced)
    # leader (highest roll) recovered so round bumps correctly on next wrap
    assert Initiative.current(Initiative.advance(restored)).combatant_id == "amy"
  end

  test "restore/2 keeps build/1's leader when the top roll is tied" do
    # amy and bob tie on 18; build/1 breaks the tie by id, so amy leads
    {:ok, i0} = Initiative.build([{"amy", 18}, {"bob", 18}, {"cat", 9}])
    live = Initiative.advance(i0)
    restored = Initiative.restore(Initiative.to_list(live), Initiative.round(live))

    # bob -> cat -> amy: the turn is back with the leader, so round 2 on both
    live = live |> Initiative.advance() |> Initiative.advance()
    restored = restored |> Initiative.advance() |> Initiative.advance()
    assert Initiative.current(restored).combatant_id == "amy"
    assert Initiative.round(live) == 2
    assert Initiative.round(restored) == 2
  end

  property "a restored ring plays out the same turns and rounds as the live one" do
    check all(
            entries <-
              uniq_list_of(tuple({string(:alphanumeric, min_length: 1), integer(1..4)}),
                uniq_fun: &elem(&1, 0),
                min_length: 1,
                max_length: 8
              ),
            before <- list_of(member_of([:advance, :rewind]), max_length: 20),
            after_restore <- list_of(member_of([:advance, :rewind]), max_length: 20)
          ) do
      {:ok, init} = Initiative.build(entries)
      live = Enum.reduce(before, init, &step/2)
      restored = Initiative.restore(Initiative.to_list(live), Initiative.round(live))

      assert trace(restored, after_restore) == trace(live, after_restore)
    end
  end

  property "advancing `size` times returns to the start; multiset preserved" do
    check all(
            entries <-
              uniq_list_of(tuple({string(:alphanumeric, min_length: 1), integer()}),
                uniq_fun: &elem(&1, 0),
                min_length: 1,
                max_length: 12
              )
          ) do
      {:ok, init} = Initiative.build(entries)
      size = length(entries)
      ids = fn i -> i |> Initiative.to_list() |> Enum.map(& &1.combatant_id) |> Enum.sort() end

      looped = Enum.reduce(1..size, init, fn _, acc -> Initiative.advance(acc) end)
      assert Initiative.current(looped).combatant_id == Initiative.current(init).combatant_id
      assert ids.(looped) == ids.(init)
    end
  end

  property "the turn and round always match the number of turns taken" do
    check all(
            entries <-
              uniq_list_of(tuple({string(:alphanumeric, min_length: 1), integer()}),
                uniq_fun: &elem(&1, 0),
                min_length: 1,
                max_length: 8
              ),
            moves <- list_of(member_of([:advance, :rewind]), max_length: 30)
          ) do
      {:ok, init} = Initiative.build(entries)
      order = init |> Initiative.to_list() |> Enum.map(& &1.combatant_id)
      size = length(order)

      # a rewind takes back one turn, but never goes before the first one
      Enum.reduce(moves, {init, 0}, fn move, {ring, taken} ->
        ring = step(move, ring)
        taken = if move == :advance, do: taken + 1, else: max(taken - 1, 0)
        assert Initiative.current(ring).combatant_id == Enum.at(order, rem(taken, size))
        assert Initiative.round(ring) == div(taken, size) + 1
        {ring, taken}
      end)
    end
  end

  defp step(:advance, ring), do: Initiative.advance(ring)
  defp step(:rewind, ring), do: Initiative.rewind(ring)

  # {current combatant, round} after each move
  defp trace(ring, moves) do
    moves
    |> Enum.scan(ring, &step/2)
    |> Enum.map(&{Initiative.current(&1).combatant_id, Initiative.round(&1)})
  end
end
