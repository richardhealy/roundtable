defmodule RoundtableWeb.TableChannelTest do
  use RoundtableWeb.ChannelCase, async: false

  alias RoundtableWeb.UserSocket

  defp connect_and_join(player_id, table_id) do
    {:ok, socket} = connect(UserSocket, %{"token" => UserSocket.sign(player_id)})
    subscribe_and_join(socket, "table:" <> table_id, %{})
  end

  setup do
    %{id: "t-" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  test "join pushes an authoritative snapshot with a seq", %{id: id} do
    {:ok, _reply, _socket} = connect_and_join("amy", id)
    assert_push "state", %{state: %{players: players}, seq: seq}
    assert is_integer(seq)
    assert Map.has_key?(players, "amy")
  end

  test "an accepted intent replies with a seq and pushes a delta", %{id: id} do
    {:ok, _reply, socket} = connect_and_join("amy", id)

    ref =
      push(socket, "intent", %{
        "type" => "set_initiative",
        "rolls" => [
          %{"combatant_id" => "amy", "roll" => 18},
          %{"combatant_id" => "bob", "roll" => 5}
        ]
      })

    assert_reply ref, :ok, %{seq: _seq}
    assert_push "delta", %{type: :initiative_set}
  end

  test "a rejected intent replies with an error and pushes no delta", %{id: id} do
    {:ok, _reply, socket} = connect_and_join("amy", id)
    ref = push(socket, "intent", %{"type" => "advance_turn"})
    assert_reply ref, :error, %{reason: "no_initiative"}
    refute_push "delta", %{type: :turn_advanced}
  end

  test "a set_initiative with a non-integer roll is rejected and the channel stays up",
       %{id: id} do
    {:ok, _reply, socket} = connect_and_join("amy", id)
    Process.flag(:trap_exit, true)

    ref =
      push(socket, "intent", %{
        "type" => "set_initiative",
        "rolls" => [
          %{"combatant_id" => "amy", "roll" => "18"},
          %{"combatant_id" => "bob", "roll" => 5}
        ]
      })

    assert_reply ref, :error, %{reason: "invalid_roll"}
    refute_push "delta", %{type: :initiative_set}
    assert Process.alive?(socket.channel_pid)

    ref = push(socket, "intent", %{"type" => "advance_turn"})
    assert_reply ref, :error, %{reason: "no_initiative"}
  end

  test "a set_initiative without a list of roll objects is rejected as bad_initiative",
       %{id: id} do
    {:ok, _reply, socket} = connect_and_join("amy", id)

    malformed = [
      %{"type" => "set_initiative"},
      %{"type" => "set_initiative", "rolls" => nil},
      %{"type" => "set_initiative", "rolls" => "amy:18"},
      %{"type" => "set_initiative", "rolls" => %{"amy" => 18}},
      %{"type" => "set_initiative", "rolls" => ["amy"]}
    ]

    for payload <- malformed do
      ref = push(socket, "intent", payload)
      assert_reply ref, :error, %{reason: "bad_initiative"}
    end

    refute_push "delta", %{type: :initiative_set}
  end

  test "an intent type the server does not know is rejected as unknown_intent", %{id: id} do
    {:ok, _reply, socket} = connect_and_join("amy", id)

    for payload <- [%{"type" => "dance"}, %{"rolls" => []}, %{}] do
      ref = push(socket, "intent", payload)
      assert_reply ref, :error, %{reason: "unknown_intent"}
    end
  end

  test "an event other than intent gets an error reply and the channel stays up", %{id: id} do
    {:ok, _reply, socket} = connect_and_join("amy", id)
    Process.flag(:trap_exit, true)

    ref = push(socket, "chat", %{"text" => "hello"})
    assert_reply ref, :error, %{reason: "unknown_event"}
    assert Process.alive?(socket.channel_pid)
    refute_received {:EXIT, _pid, _reason}

    ref = push(socket, "intent", %{"type" => "advance_turn"})
    assert_reply ref, :error, %{reason: "no_initiative"}
  end

  test "connecting with a bad token is refused" do
    assert :error = connect(UserSocket, %{"token" => "garbage"})
  end
end
