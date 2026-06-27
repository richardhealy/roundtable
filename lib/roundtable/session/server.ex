defmodule Roundtable.Session.Server do
  @moduledoc """
  Authoritative GenServer for one table. Serializes intents, stamps each
  accepted change with a `:atomics` sequence number, and broadcasts the delta
  to the table topic via `Phoenix.PubSub`.
  """
  use GenServer

  alias Roundtable.Session
  alias Roundtable.Session.Seq
  alias Roundtable.TableState

  @type state :: %{table_state: TableState.t(), seq: Seq.ref()}

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(table_id) do
    GenServer.start_link(__MODULE__, table_id, name: Session.Registry.via(table_id))
  end

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(table_id) do
    %{
      id: {__MODULE__, table_id},
      start: {__MODULE__, :start_link, [table_id]},
      restart: :transient
    }
  end

  @impl true
  def init(table_id) do
    {:ok, %{table_state: TableState.new(table_id), seq: Seq.new()}}
  end

  @impl true
  def handle_call({:apply_intent, intent}, _from, state) do
    case TableState.apply_intent(state.table_state, intent) do
      {:ok, ts, delta} ->
        seq = Seq.next(state.seq)
        ts = %{ts | last_seq: seq}
        broadcast(ts.table_id, Map.put(delta, :seq, seq))
        {:reply, {:ok, seq}, %{state | table_state: ts}}

      :noop ->
        {:reply, {:ok, :noop}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {TableState.snapshot(state.table_state), Seq.current(state.seq)}, state}
  end

  defp broadcast(table_id, delta) do
    Phoenix.PubSub.broadcast(Roundtable.PubSub, Session.topic(table_id), {:delta, delta})
  end
end
