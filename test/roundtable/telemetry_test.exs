defmodule Roundtable.TelemetryTest do
  use ExUnit.Case, async: true

  alias Roundtable.Telemetry

  defp attach(event) do
    test_pid = self()
    id = {__MODULE__, event, make_ref()}

    :telemetry.attach(
      id,
      event,
      fn name, meas, meta, _ -> send(test_pid, {:telemetry, name, meas, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  test "intent_stop/4 emits duration + result" do
    attach([:roundtable, :session, :intent, :stop])
    assert Telemetry.intent_stop("t1", :join, :accepted, 1234) == :ok

    assert_receive {:telemetry, [:roundtable, :session, :intent, :stop], %{duration: 1234},
                    %{table_id: "t1", type: :join, result: :accepted}}
  end

  test "session_started/2 emits restored flag" do
    attach([:roundtable, :session, :started])
    Telemetry.session_started("t1", true)

    assert_receive {:telemetry, [:roundtable, :session, :started], %{count: 1},
                    %{table_id: "t1", restored: true}}
  end

  test "delta_broadcast/2 emits type" do
    attach([:roundtable, :delta, :broadcast])
    Telemetry.delta_broadcast("t1", :player_joined)

    assert_receive {:telemetry, [:roundtable, :delta, :broadcast], %{count: 1},
                    %{table_id: "t1", type: :player_joined}}
  end
end
