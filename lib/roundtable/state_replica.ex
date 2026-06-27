defmodule Roundtable.StateReplica do
  @moduledoc """
  Cluster-replicated store of the latest authoritative snapshot per table, backed
  by a `DeltaCrdt.AWLWWMap`. Each `Session.Server` writes here on every accepted
  intent; on (re)start a session restores from here. Replication lets a table
  survive an ungraceful node kill — the snapshot is already on the surviving
  nodes when Horde restarts the session there.
  """
  use GenServer

  @crdt __MODULE__.Crdt
  @sync_interval 100

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Store the latest snapshot for `table_id`."
  @spec put(term(), map()) :: :ok
  def put(table_id, snapshot) do
    DeltaCrdt.put(@crdt, table_id, snapshot)
    :ok
  end

  @doc "Read the latest snapshot for `table_id`, or `nil`."
  @spec get(term()) :: map() | nil
  def get(table_id) do
    @crdt |> DeltaCrdt.to_map() |> Map.get(table_id)
  end

  @impl true
  def init(:ok) do
    {:ok, crdt} =
      DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, name: @crdt, sync_interval: @sync_interval)

    :net_kernel.monitor_nodes(true)
    set_neighbours()
    {:ok, %{crdt: crdt}}
  end

  @impl true
  def handle_info({event, _node}, state) when event in [:nodeup, :nodedown] do
    set_neighbours()
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp set_neighbours do
    neighbours = for n <- Node.list(), do: {@crdt, n}
    DeltaCrdt.set_neighbours(@crdt, neighbours)
  end
end
