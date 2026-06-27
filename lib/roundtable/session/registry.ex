defmodule Roundtable.Session.Registry do
  @moduledoc """
  Lookup wrapper for per-table session processes.

  Single-node backing is a local `Registry`. Confining every lookup here keeps
  the M5 swap to a distributed registry (Horde) a one-module change.
  """

  @registry __MODULE__

  @doc "Child spec to start the underlying registry."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  @doc "A `:via` tuple naming the session process for `table_id`."
  @spec via(term()) :: {:via, Registry, {module(), term()}}
  def via(table_id), do: {:via, Registry, {@registry, table_id}}

  @doc "The pid for `table_id`, or `nil`."
  @spec whereis(term()) :: pid() | nil
  def whereis(table_id) do
    case Registry.lookup(@registry, table_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
