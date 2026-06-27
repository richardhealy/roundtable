defmodule Roundtable.Session.Supervisor do
  @moduledoc "DynamicSupervisor owning one `Session.Server` per live table."
  use DynamicSupervisor

  alias Roundtable.Session.Server

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Start a session for `table_id` under supervision."
  @spec start_session(term()) :: DynamicSupervisor.on_start_child()
  def start_session(table_id) do
    DynamicSupervisor.start_child(__MODULE__, {Server, table_id})
  end
end
