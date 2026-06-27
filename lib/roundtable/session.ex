defmodule Roundtable.Session do
  @moduledoc """
  Public API for working with table sessions: find-or-start a table's process,
  apply intents, and read the authoritative snapshot. Hides the registry and
  supervisor from callers (the channel and tests).
  """

  alias Roundtable.Session.{Registry, Supervisor}
  alias Roundtable.TableState

  @doc "The PubSub topic deltas for `table_id` are broadcast on."
  @spec topic(term()) :: String.t()
  def topic(table_id), do: "table:" <> to_string(table_id)

  @doc "Return the running session pid for `table_id`, starting it if needed."
  @spec find_or_start(term()) :: {:ok, pid()}
  def find_or_start(table_id) do
    case Registry.whereis(table_id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case Supervisor.start_session(table_id) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
        end
    end
  end

  @doc "Apply an intent to `table_id`, starting the session if needed."
  @spec apply_intent(term(), TableState.intent()) ::
          {:ok, pos_integer()} | {:ok, :noop} | {:error, atom()}
  def apply_intent(table_id, intent) do
    {:ok, pid} = find_or_start(table_id)
    GenServer.call(pid, {:apply_intent, intent})
  end

  @doc "Return `{snapshot, current_seq}` for `table_id`, starting the session if needed."
  @spec get_state(term()) :: {map(), non_neg_integer()}
  def get_state(table_id) do
    {:ok, pid} = find_or_start(table_id)
    GenServer.call(pid, :get_state)
  end
end
