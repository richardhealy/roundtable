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

  describe "active session queries" do
    alias Roundtable.Session

    test "active_count and active_sessions reflect running tables, dispatch emits count" do
      id = "t-" <> Integer.to_string(System.unique_integer([:positive]))
      {:ok, 1} = Session.apply_intent(id, {:join, "amy", %{}})
      {:ok, 2} = Session.apply_intent(id, {:set_initiative, [{"amy", 18}, {"bob", 9}]})

      assert Telemetry.active_count() >= 1
      row = Enum.find(Telemetry.active_sessions(), &(&1.table_id == id))
      assert row.players == 1
      assert row.current == "amy"
      assert row.last_seq == 2

      test_pid = self()

      :telemetry.attach(
        {__MODULE__, :count, make_ref()},
        [:roundtable, :sessions],
        fn _n, meas, _meta, _ -> send(test_pid, {:count, meas}) end,
        nil
      )

      assert Telemetry.dispatch_session_count() == :ok
      assert_receive {:count, %{count: n}} when is_integer(n) and n >= 1
    end
  end
end
