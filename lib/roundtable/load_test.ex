defmodule Roundtable.LoadTest do
  @moduledoc """
  In-node load harness: spawn many sessions, measure memory per session and the
  broadcast latency of the `apply_intent`→`{:delta, _}` path, and report
  percentiles. Drives sessions directly (not over the websocket transport).
  """

  alias Roundtable.Session

  @type result :: %{
          sessions: pos_integer(),
          memory_per_session_kb: float(),
          latency_us: %{p50: number(), p99: number(), p999: number()},
          samples: pos_integer(),
          elapsed_ms: integer()
        }

  @doc "Spawn `n` sessions, measure memory/session and broadcast latency, tear down."
  @spec run(pos_integer(), keyword()) :: result()
  def run(n, opts \\ []) when n > 0 do
    samples = Keyword.get(opts, :samples, min(n, 1000))
    ids = for i <- 1..n, do: "load-#{System.unique_integer([:positive])}-#{i}"

    :erlang.garbage_collect()
    before_mem = :erlang.memory(:total)
    t_start = System.monotonic_time(:millisecond)

    ids
    |> Task.async_stream(
      fn id -> Session.apply_intent(id, {:join, "p1", %{}}) end,
      max_concurrency: System.schedulers_online() * 4,
      timeout: 60_000
    )
    |> Stream.run()

    gc_sessions(ids)
    after_mem = :erlang.memory(:total)
    mem_per_session_kb = (after_mem - before_mem) / n / 1024

    sorted = ids |> Enum.take_random(samples) |> Enum.map(&measure_latency/1) |> Enum.sort()
    elapsed = System.monotonic_time(:millisecond) - t_start

    teardown(ids)

    %{
      sessions: n,
      memory_per_session_kb: Float.round(mem_per_session_kb, 2),
      latency_us: %{
        p50: percentile(sorted, 50),
        p99: percentile(sorted, 99),
        p999: percentile(sorted, 99.9)
      },
      samples: samples,
      elapsed_ms: elapsed
    }
  end

  defp measure_latency(id) do
    topic = Session.topic(id)
    :ok = Phoenix.PubSub.subscribe(Roundtable.PubSub, topic)
    t0 = System.monotonic_time(:microsecond)
    Session.apply_intent(id, {:set_initiative, [{"a", 1}]})

    receive do
      {:delta, _} -> :ok
    after
      5_000 -> :timeout
    end

    t1 = System.monotonic_time(:microsecond)
    Phoenix.PubSub.unsubscribe(Roundtable.PubSub, topic)
    t1 - t0
  end

  defp gc_sessions(ids) do
    for id <- ids, pid = Session.Registry.whereis(id), is_pid(pid), do: :erlang.garbage_collect(pid)
    :ok
  end

  defp teardown(ids) do
    for id <- ids, pid = Session.Registry.whereis(id), is_pid(pid) do
      Horde.DynamicSupervisor.terminate_child(Session.Supervisor, pid)
    end

    :ok
  end

  @doc "Nearest-rank percentile over an ascending-sorted list (0 for empty)."
  @spec percentile([number()], number()) :: number()
  def percentile([], _p), do: 0

  def percentile(sorted, p) do
    n = length(sorted)
    idx = (p / 100 * n) |> Float.ceil() |> trunc() |> max(1) |> min(n)
    Enum.at(sorted, idx - 1)
  end
end
