defmodule Roundtable.Initiative do
  @moduledoc """
  Turn order as an O(1) ring built on Erlang's `:queue`.

  The front of the queue is whose turn it is. `advance/1` moves the front to
  the back (`:queue.out` + `:queue.in`); `rewind/1` is the inverse
  (`:queue.out_r` + `:queue.in_r`). A `round` counter increments each time the
  turn returns to the `leader` (the highest-initiative combatant). Pure: no
  time, no randomness, no process calls.
  """

  @enforce_keys [:queue, :round, :size, :leader]
  defstruct [:queue, :round, :size, :leader]

  @type entry :: %{combatant_id: term(), roll: integer()}
  @type t :: %__MODULE__{
          queue: :queue.queue(entry()),
          round: pos_integer(),
          size: pos_integer(),
          leader: term()
        }

  @doc """
  Build a ring from `{combatant_id, roll}` pairs, ordered by roll desc then id asc.

  Rolls arrive from clients, so a roll that is not an integer is rejected with
  `{:error, :invalid_roll}` rather than raising inside the session process.
  """
  @spec build([{term(), integer()}]) ::
          {:ok, t()} | {:error, :empty | :duplicate_combatant | :invalid_roll}
  def build([]), do: {:error, :empty}

  def build(rolls) when is_list(rolls) do
    ids = Enum.map(rolls, &elem(&1, 0))

    cond do
      length(Enum.uniq(ids)) != length(ids) ->
        {:error, :duplicate_combatant}

      not Enum.all?(rolls, fn {_id, roll} -> is_integer(roll) end) ->
        {:error, :invalid_roll}

      true ->
        {:ok, ring(rolls)}
    end
  end

  defp ring(rolls) do
    ordered =
      rolls
      |> Enum.sort_by(fn {id, roll} -> {-roll, id} end)
      |> Enum.map(fn {id, roll} -> %{combatant_id: id, roll: roll} end)

    %__MODULE__{
      queue: :queue.from_list(ordered),
      round: 1,
      size: length(ordered),
      leader: hd(ordered).combatant_id
    }
  end

  @doc "Rebuild a ring from a snapshot's rotation order (current first) and round."
  @spec restore([entry()], pos_integer()) :: t()
  def restore([_ | _] = order, round) do
    %__MODULE__{
      queue: :queue.from_list(order),
      round: round,
      size: length(order),
      leader: Enum.max_by(order, & &1.roll).combatant_id
    }
  end

  @doc "The combatant whose turn it currently is."
  @spec current(t()) :: entry()
  def current(%__MODULE__{queue: q}) do
    {:value, entry} = :queue.peek(q)
    entry
  end

  @doc "The current rotation order, front first."
  @spec to_list(t()) :: [entry()]
  def to_list(%__MODULE__{queue: q}), do: :queue.to_list(q)

  @doc "The current round number (1-based)."
  @spec round(t()) :: pos_integer()
  def round(%__MODULE__{round: r}), do: r

  @doc "Advance to the next combatant, bumping `round` when the turn returns to the leader."
  @spec advance(t()) :: t()
  def advance(%__MODULE__{queue: q, round: r, leader: leader} = init) do
    {{:value, head}, rest} = :queue.out(q)
    rotated = :queue.in(head, rest)
    round = if front_id(rotated) == leader, do: r + 1, else: r
    %{init | queue: rotated, round: round}
  end

  @doc "Step back to the previous combatant, decrementing `round` on wrap (floors at 1)."
  @spec rewind(t()) :: t()
  def rewind(%__MODULE__{queue: q, round: r, leader: leader} = init) do
    crossing_back = front_id(q) == leader and r > 1
    {{:value, tail}, rest} = :queue.out_r(q)
    rotated = :queue.in_r(tail, rest)
    round = if crossing_back, do: r - 1, else: r
    %{init | queue: rotated, round: round}
  end

  defp front_id(q) do
    {:value, entry} = :queue.peek(q)
    entry.combatant_id
  end
end
