defmodule Roundtable.StateReplicaTest do
  use ExUnit.Case, async: false

  alias Roundtable.StateReplica

  test "put then get round-trips a snapshot" do
    key = "t-" <> Integer.to_string(System.unique_integer([:positive]))
    assert StateReplica.get(key) == nil
    snap = %{table_id: key, players: %{"amy" => %{meta: %{}}}, initiative: nil, last_seq: 1}
    assert StateReplica.put(key, snap) == :ok
    assert StateReplica.get(key) == snap
  end
end
