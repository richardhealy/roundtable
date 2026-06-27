defmodule Mix.Tasks.Roundtable.Loadtest do
  @shortdoc "Spawn N sessions and report memory/session + broadcast latency"
  @moduledoc """
  Load-test the session core in-node.

      mix roundtable.loadtest 10000
  """
  use Mix.Task

  @impl true
  def run(args) do
    n =
      case args do
        [arg | _] -> String.to_integer(arg)
        [] -> 1000
      end

    Mix.Task.run("app.start")
    r = Roundtable.LoadTest.run(n)
    l = r.latency_us

    Mix.shell().info("""

    roundtable load test
    ─────────────────────────────────────────────
      sessions             #{r.sessions}
      memory / session     #{r.memory_per_session_kb} KB
      broadcast latency    p50 #{l.p50}µs  p99 #{l.p99}µs  p99.9 #{l.p999}µs
      latency samples      #{r.samples}
      elapsed              #{r.elapsed_ms} ms
    ─────────────────────────────────────────────
    """)
  end
end
