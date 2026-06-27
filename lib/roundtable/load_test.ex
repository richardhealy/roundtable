defmodule Roundtable.LoadTest do
  @moduledoc """
  In-node load harness: spawn many sessions, measure memory per session and the
  broadcast latency of the `apply_intent`→`{:delta, _}` path, and report
  percentiles. Drives sessions directly (not over the websocket transport).
  """

  @doc "Nearest-rank percentile over an ascending-sorted list (0 for empty)."
  @spec percentile([number()], number()) :: number()
  def percentile([], _p), do: 0

  def percentile(sorted, p) do
    n = length(sorted)
    idx = (p / 100 * n) |> Float.ceil() |> trunc() |> max(1) |> min(n)
    Enum.at(sorted, idx - 1)
  end
end
