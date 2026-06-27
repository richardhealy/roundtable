defmodule Roundtable.TableStateTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Roundtable.Initiative
  alias Roundtable.TableState

  test "join adds a player and emits a delta; re-join is a no-op" do
    ts = TableState.new("t1")
    assert {:ok, ts, delta} = TableState.apply_intent(ts, {:join, "amy", %{class: "rogue"}})
    assert delta.type == :player_joined
    assert delta.payload.player_id == "amy"
    assert Map.has_key?(ts.players, "amy")
    assert TableState.apply_intent(ts, {:join, "amy", %{}}) == :noop
  end

  test "leave removes a known player; leaving a stranger errors" do
    ts = TableState.new("t1")
    {:ok, ts, _} = TableState.apply_intent(ts, {:join, "amy", %{}})
    assert {:ok, ts, delta} = TableState.apply_intent(ts, {:leave, "amy"})
    assert delta.type == :player_left
    refute Map.has_key?(ts.players, "amy")
    assert TableState.apply_intent(ts, {:leave, "amy"}) == {:error, :not_a_player}
  end

  test "set_initiative installs a ring; bad rosters error" do
    ts = TableState.new("t1")

    assert {:ok, ts, delta} =
             TableState.apply_intent(ts, {:set_initiative, [{"amy", 18}, {"bob", 7}]})

    assert delta.type == :initiative_set
    assert hd(delta.payload.order).combatant_id == "amy"
    assert {:error, :empty} = TableState.apply_intent(ts, {:set_initiative, []})
  end

  test "advance/rewind require initiative and emit turn deltas" do
    ts = TableState.new("t1")
    assert {:error, :no_initiative} = TableState.apply_intent(ts, :advance_turn)
    {:ok, ts, _} = TableState.apply_intent(ts, {:set_initiative, [{"amy", 18}, {"bob", 7}]})
    assert {:ok, ts, delta} = TableState.apply_intent(ts, :advance_turn)
    assert delta.type == :turn_advanced
    assert delta.payload.current == "bob"
    assert {:ok, _ts, d2} = TableState.apply_intent(ts, :rewind_turn)
    assert d2.payload.current == "amy"
  end

  test "from_snapshot/1 inverts snapshot/1" do
    ts = TableState.new("t1")
    {:ok, ts, _} = TableState.apply_intent(ts, {:join, "amy", %{x: 1}})
    {:ok, ts, _} = TableState.apply_intent(ts, {:set_initiative, [{"amy", 18}, {"bob", 9}]})
    {:ok, ts, _} = TableState.apply_intent(ts, :advance_turn)
    ts = %{ts | last_seq: 3}
    restored = TableState.from_snapshot(TableState.snapshot(ts))
    assert restored.players == ts.players
    assert restored.last_seq == 3

    assert Initiative.current(restored.initiative).combatant_id ==
             Initiative.current(ts.initiative).combatant_id

    assert TableState.snapshot(restored) == TableState.snapshot(ts)
  end

  property "any sequence of valid intents keeps players a map and initiative well-formed" do
    intents =
      one_of([
        tuple({constant(:join), string(:alphanumeric, min_length: 1), constant(%{})}),
        tuple({constant(:leave), string(:alphanumeric, min_length: 1)}),
        constant(:advance_turn),
        constant(:rewind_turn)
      ])

    check all(ops <- list_of(intents, max_length: 40)) do
      final =
        Enum.reduce(ops, TableState.new("t1"), fn intent, ts ->
          case TableState.apply_intent(ts, intent) do
            {:ok, next, _delta} -> next
            _ -> ts
          end
        end)

      assert is_map(final.players)
      assert final.initiative == nil or match?(%Roundtable.Initiative{}, final.initiative)
    end
  end
end
