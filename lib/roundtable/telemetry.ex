defmodule Roundtable.Telemetry do
  @moduledoc """
  Instrumentation for the session hot paths: one home for Telemetry event names,
  the emit helpers called by `Session.Server`, the periodic active-session
  measurement, and the queries that back the LiveDashboard Sessions page.
  """

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
end
