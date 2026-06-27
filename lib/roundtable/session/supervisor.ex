defmodule Roundtable.Session.Supervisor do
  @moduledoc """
  Cluster-wide supervisor of session processes, backed by `Horde.DynamicSupervisor`.
  `process_redistribution: :active` migrates a node's sessions onto survivors when
  membership changes; `members: :auto` tracks connected nodes. `start_session/1` is
  unchanged from the single-node version.
  """

  alias Roundtable.Session.Server

  @sup __MODULE__

  @doc "Child spec to start the underlying Horde dynamic supervisor."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Supervisor.child_spec(
      {Horde.DynamicSupervisor,
       name: @sup, strategy: :one_for_one, members: :auto, process_redistribution: :active},
      id: @sup
    )
  end

  @doc "Start a session for `table_id` under supervision."
  @spec start_session(term()) :: {:ok, pid()} | {:error, term()}
  def start_session(table_id) do
    Horde.DynamicSupervisor.start_child(@sup, {Server, table_id})
  end
end
