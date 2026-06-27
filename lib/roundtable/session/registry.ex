defmodule Roundtable.Session.Registry do
  @moduledoc """
  Cluster-wide lookup for per-table session processes, backed by `Horde.Registry`
  (`members: :auto` tracks connected nodes). The `via/1` and `whereis/1` surface is
  unchanged from the single-node version, so callers don't change.
  """

  @registry __MODULE__

  @doc "Child spec to start the underlying Horde registry."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Supervisor.child_spec(
      {Horde.Registry, name: @registry, keys: :unique, members: :auto},
      id: @registry
    )
  end

  @doc "A `:via` tuple naming the session process for `table_id`."
  @spec via(term()) :: {:via, Horde.Registry, {module(), term()}}
  def via(table_id), do: {:via, Horde.Registry, {@registry, table_id}}

  @doc "The pid for `table_id`, or `nil`."
  @spec whereis(term()) :: pid() | nil
  def whereis(table_id) do
    case Horde.Registry.lookup(@registry, table_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
