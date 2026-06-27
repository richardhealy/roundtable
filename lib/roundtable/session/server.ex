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
    seq = Seq.new()

    {table_state, restored?} =
      case Roundtable.StateReplica.get(table_id) do
        nil ->
          {TableState.new(table_id), false}

        snapshot ->
          Seq.set(seq, snapshot.last_seq)
          {TableState.from_snapshot(snapshot), true}
      end

    Roundtable.Telemetry.session_started(table_id, restored?)
    {:ok, %{table_state: table_state, seq: seq}}
  end

  @impl true
  def handle_call({:apply_intent, intent}, _from, state) do
    start = System.monotonic_time()

    {reply, new_state, result} =
      case TableState.apply_intent(state.table_state, intent) do
        {:ok, ts, delta} ->
          seq = Seq.next(state.seq)
          ts = %{ts | last_seq: seq}
          Roundtable.StateReplica.put(ts.table_id, TableState.snapshot(ts))
          broadcast(ts.table_id, Map.put(delta, :seq, seq))
          {{:ok, seq}, %{state | table_state: ts}, :accepted}

        :noop ->
          {{:ok, :noop}, state, :noop}

        {:error, reason} ->
          {{:error, reason}, state, :rejected}
      end

    duration = System.monotonic_time() - start

    Roundtable.Telemetry.intent_stop(
      state.table_state.table_id,
      intent_type(intent),
      result,
      duration
    )

    {:reply, reply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {TableState.snapshot(state.table_state), Seq.current(state.seq)}, state}
  end

  defp intent_type({:join, _, _}), do: :join
  defp intent_type({:leave, _}), do: :leave
  defp intent_type({:set_initiative, _}), do: :set_initiative
  defp intent_type(:advance_turn), do: :advance_turn
  defp intent_type(:rewind_turn), do: :rewind_turn

  defp broadcast(table_id, delta) do
    Roundtable.Telemetry.delta_broadcast(table_id, delta.type)
    Phoenix.PubSub.broadcast(Roundtable.PubSub, Session.topic(table_id), {:delta, delta})
  end
end
