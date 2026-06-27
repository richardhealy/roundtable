defmodule Roundtable.SessionTest do
  use ExUnit.Case, async: false

  alias Roundtable.Session

  setup do
    # unique id per test so concurrent tables don't collide
    %{id: "t-" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  test "find_or_start is idempotent and returns the same pid", %{id: id} do
    {:ok, pid} = Session.find_or_start(id)
    assert {:ok, ^pid} = Session.find_or_start(id)
  end

  test "accepted intents broadcast seq'd deltas in monotonic order", %{id: id} do
    Phoenix.PubSub.subscribe(Roundtable.PubSub, Session.topic(id))
    {:ok, 1} = Session.apply_intent(id, {:join, "amy", %{}})
    {:ok, 2} = Session.apply_intent(id, {:set_initiative, [{"amy", 18}, {"bob", 9}]})
    {:ok, 3} = Session.apply_intent(id, :advance_turn)

    assert_receive {:delta, %{seq: 1, type: :player_joined}}
    assert_receive {:delta, %{seq: 2, type: :initiative_set}}
    assert_receive {:delta, %{seq: 3, type: :turn_advanced, payload: %{current: "bob"}}}
  end

  test "rejected and no-op intents neither consume seq nor broadcast", %{id: id} do
    Phoenix.PubSub.subscribe(Roundtable.PubSub, Session.topic(id))
    {:ok, 1} = Session.apply_intent(id, {:join, "amy", %{}})
    assert {:ok, :noop} = Session.apply_intent(id, {:join, "amy", %{}})
    assert {:error, :not_a_player} = Session.apply_intent(id, {:leave, "zzz"})
    {:ok, 2} = Session.apply_intent(id, {:leave, "amy"})

    assert_receive {:delta, %{seq: 1}}
    assert_receive {:delta, %{seq: 2}}
    refute_received {:delta, %{seq: 3}}
  end

  test "get_state returns snapshot + current seq", %{id: id} do
    {:ok, 1} = Session.apply_intent(id, {:join, "amy", %{}})
    {snapshot, seq} = Session.get_state(id)
    assert seq == 1
    assert Map.has_key?(snapshot.players, "amy")
  end

  test "crashing one table does not disturb another", %{id: id} do
    other = id <> "-other"
    {:ok, pid_a} = Session.find_or_start(id)
    {:ok, 1} = Session.apply_intent(other, {:join, "z", %{}})
    {:ok, pid_b} = Session.find_or_start(other)

    Process.exit(pid_a, :kill)
    Process.sleep(50)

    assert Process.alive?(pid_b)
    # table A restarts fresh on next use
    {snapshot, _seq} = Session.get_state(id)
    assert snapshot.players == %{}
  end
end
