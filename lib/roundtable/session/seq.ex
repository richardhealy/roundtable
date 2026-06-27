defmodule Roundtable.Session.Seq do
  @moduledoc """
  Thin Elixir wrapper over the native Erlang `:roundtable_seq` module.

  Each table owns one sequence ref. `next/1` hands out strictly-monotonic,
  lock-free sequence numbers used to order and deduplicate broadcast deltas.
  """

  @type ref :: :atomics.atomics_ref()

  @doc "Allocate a new per-table sequence counter starting at 0."
  @spec new() :: ref()
  def new, do: :roundtable_seq.new()

  @doc "Atomically increment and return the next sequence number (>= 1)."
  @spec next(ref()) :: pos_integer()
  def next(ref), do: :roundtable_seq.next(ref)

  @doc "Read the current sequence number without consuming one."
  @spec current(ref()) :: non_neg_integer()
  def current(ref), do: :roundtable_seq.current(ref)
end
