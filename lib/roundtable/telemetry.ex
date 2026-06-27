defmodule Roundtable.Telemetry do
  @moduledoc """
  Instrumentation for the session hot paths: one home for Telemetry event names,
  the emit helpers called by `Session.Server`, the periodic active-session
  measurement, and the queries that back the LiveDashboard Sessions page.
  """

  alias Roundtable.{Session, StateReplica}

  @doc "Emit the end of intent processing with its duration and result."
  @spec intent_stop(term(), atom(), :accepted | :rejected | :noop, integer()) :: :ok
  def intent_stop(table_id, type, result, duration) do
    :telemetry.execute(
      [:roundtable, :session, :intent, :stop],
      %{duration: duration},
      %{table_id: table_id, type: type, result: result}
    )
  end

  @doc "Emit that a session started, noting whether it restored from the replica."
  @spec session_started(term(), boolean()) :: :ok
  def session_started(table_id, restored?) do
    :telemetry.execute(
      [:roundtable, :session, :started],
      %{count: 1},
      %{table_id: table_id, restored: restored?}
    )
  end

  @doc "Emit that a delta was broadcast for a table."
  @spec delta_broadcast(term(), atom()) :: :ok
  def delta_broadcast(table_id, type) do
    :telemetry.execute(
      [:roundtable, :delta, :broadcast],
      %{count: 1},
      %{table_id: table_id, type: type}
    )
  end

  @doc "Number of active session processes."
  @spec active_count() :: non_neg_integer()
  def active_count do
    Session.Supervisor
    |> Horde.DynamicSupervisor.count_children()
    |> Map.get(:active, 0)
  end

  @doc "Emit the active-session count as a periodic gauge measurement."
  @spec dispatch_session_count() :: :ok
  def dispatch_session_count do
    :telemetry.execute([:roundtable, :sessions], %{count: active_count()}, %{})
  end

  @doc "Rows describing each active table, for the LiveDashboard Sessions page."
  @spec active_sessions() :: [
          %{
            table_id: term(),
            players: non_neg_integer(),
            current: term() | nil,
            round: pos_integer() | nil,
            last_seq: non_neg_integer()
          }
        ]
  def active_sessions do
    snapshots = StateReplica.all()

    for table_id <- active_ids(), snap = Map.get(snapshots, table_id), snap != nil do
      %{
        table_id: table_id,
        players: map_size(snap.players),
        current: current_of(snap),
        round: round_of(snap),
        last_seq: snap.last_seq
      }
    end
  end

  defp active_ids do
    Horde.Registry.select(Session.Registry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  defp current_of(%{initiative: %{current: c}}), do: c
  defp current_of(_), do: nil

  defp round_of(%{initiative: %{round: r}}), do: r
  defp round_of(_), do: nil
end
