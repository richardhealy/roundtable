defmodule Roundtable.TableState do
  @moduledoc """
  Authoritative state for one table and the pure transition function over it.

  `apply_intent/2` validates and applies a client intent, returning the new
  state plus a delta payload to broadcast — or `:noop` / `{:error, reason}`.
  It is pure: it allocates no sequence numbers, performs no broadcasts, and
  reads no clock. The owning `Session.Server` adds the seq and broadcasts.
  """

  alias Roundtable.Initiative

  @enforce_keys [:table_id]
  defstruct table_id: nil, players: %{}, initiative: nil, last_seq: 0

  @type player :: %{meta: map()}
  @type t :: %__MODULE__{
          table_id: term(),
          players: %{optional(term()) => player()},
          initiative: Initiative.t() | nil,
          last_seq: non_neg_integer()
        }

  @type intent ::
          {:join, term(), map()}
          | {:leave, term()}
          | {:set_initiative, [{term(), integer()}]}
          | :advance_turn
          | :rewind_turn

  @type delta :: %{type: atom(), payload: map()}

  @doc "A fresh, empty table."
  @spec new(term()) :: t()
  def new(table_id), do: %__MODULE__{table_id: table_id}

  @doc "Validate and apply an intent. Pure — no seq, no broadcast, no clock."
  @spec apply_intent(t(), intent()) :: {:ok, t(), delta()} | :noop | {:error, atom()}
  def apply_intent(%__MODULE__{players: players} = ts, {:join, player_id, meta}) do
    if Map.has_key?(players, player_id) do
      :noop
    else
      ts = %{ts | players: Map.put(players, player_id, %{meta: meta})}
      {:ok, ts, %{type: :player_joined, payload: %{player_id: player_id, meta: meta}}}
    end
  end

  def apply_intent(%__MODULE__{players: players} = ts, {:leave, player_id}) do
    if Map.has_key?(players, player_id) do
      ts = %{ts | players: Map.delete(players, player_id)}
      {:ok, ts, %{type: :player_left, payload: %{player_id: player_id}}}
    else
      {:error, :not_a_player}
    end
  end

  def apply_intent(%__MODULE__{} = ts, {:set_initiative, rolls}) do
    case Initiative.build(rolls) do
      {:ok, init} ->
        ts = %{ts | initiative: init}

        payload = %{
          order: Initiative.to_list(init),
          current: Initiative.current(init).combatant_id,
          round: Initiative.round(init)
        }

        {:ok, ts, %{type: :initiative_set, payload: payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def apply_intent(%__MODULE__{initiative: nil}, intent)
      when intent in [:advance_turn, :rewind_turn],
      do: {:error, :no_initiative}

  def apply_intent(%__MODULE__{initiative: init} = ts, :advance_turn),
    do: turn(ts, Initiative.advance(init), :turn_advanced)

  # Rewinding the first turn of combat changes nothing, so it is a no-op (no
  # seq, no broadcast) rather than a delta that repeats the current turn.
  def apply_intent(%__MODULE__{initiative: init} = ts, :rewind_turn) do
    if Initiative.first_turn?(init) do
      :noop
    else
      turn(ts, Initiative.rewind(init), :turn_rewound)
    end
  end

  defp turn(ts, init, type) do
    payload = %{current: Initiative.current(init).combatant_id, round: Initiative.round(init)}
    {:ok, %{ts | initiative: init}, %{type: type, payload: payload}}
  end

  @doc "Reconstruct a table from a `snapshot/1` map (used to restore a session)."
  @spec from_snapshot(map()) :: t()
  def from_snapshot(%{table_id: id, players: players, last_seq: seq, initiative: init}) do
    %__MODULE__{
      table_id: id,
      players: players,
      last_seq: seq,
      initiative: restore_initiative(init)
    }
  end

  defp restore_initiative(nil), do: nil
  defp restore_initiative(%{order: order, round: round}), do: Initiative.restore(order, round)

  @doc "A JSON-serializable snapshot of the authoritative state."
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = ts) do
    %{
      table_id: ts.table_id,
      players: ts.players,
      last_seq: ts.last_seq,
      initiative: snapshot_initiative(ts.initiative)
    }
  end

  defp snapshot_initiative(nil), do: nil

  defp snapshot_initiative(%Initiative{} = init) do
    %{
      order: Initiative.to_list(init),
      current: Initiative.current(init).combatant_id,
      round: Initiative.round(init)
    }
  end
end
