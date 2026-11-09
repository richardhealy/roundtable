defmodule RoundtableWeb.TableChannel do
  @moduledoc """
  Client transport for one table. The channel is already subscribed to its
  topic, so seq'd deltas broadcast by the session arrive here as `{:delta, _}`
  and are pushed to the client. On join it tracks Presence, applies a `:join`
  intent, and pushes the current authoritative snapshot so a reconnecting
  client resyncs deterministically.
  """
  use RoundtableWeb, :channel

  alias Roundtable.Session
  alias RoundtableWeb.Presence

  @impl true
  def join("table:" <> table_id, _params, socket) do
    socket = assign(socket, :table_id, table_id)
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    %{table_id: table_id, player_id: player_id} = socket.assigns
    {:ok, _ref} = Presence.track(socket, player_id, %{online_at: System.system_time(:second)})
    push(socket, "presence_state", Presence.list(socket))

    # Authoritative join (idempotent) happens before we read the snapshot so the
    # snapshot already reflects this player. Deltas are deduped by seq client-side.
    _ = Session.apply_intent(table_id, {:join, player_id, %{}})
    {snapshot, seq} = Session.get_state(table_id)
    push(socket, "state", %{state: snapshot, seq: seq})
    {:noreply, socket}
  end

  def handle_info({:delta, delta}, socket) do
    push(socket, "delta", delta)
    {:noreply, socket}
  end

  @impl true
  def handle_in("intent", payload, socket) do
    case decode_intent(payload, socket.assigns.player_id) do
      {:ok, intent} ->
        reply_for(Session.apply_intent(socket.assigns.table_id, intent), socket)

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Clients only send "intent". Without this clause any other event name would
  # crash the channel process (no matching handle_in/3), and Presence would drop
  # the player until the client rejoined.
  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  defp reply_for({:ok, :noop}, socket), do: {:reply, {:ok, %{seq: "noop"}}, socket}
  defp reply_for({:ok, seq}, socket), do: {:reply, {:ok, %{seq: seq}}, socket}

  defp reply_for({:error, reason}, socket),
    do: {:reply, {:error, %{reason: to_string(reason)}}, socket}

  defp decode_intent(%{"type" => "leave"}, player_id), do: {:ok, {:leave, player_id}}
  defp decode_intent(%{"type" => "advance_turn"}, _pid), do: {:ok, :advance_turn}
  defp decode_intent(%{"type" => "rewind_turn"}, _pid), do: {:ok, :rewind_turn}

  defp decode_intent(%{"type" => "set_initiative", "rolls" => rolls}, _pid)
       when is_list(rolls) do
    parsed = Enum.map(rolls, fn %{"combatant_id" => id, "roll" => roll} -> {id, roll} end)
    {:ok, {:set_initiative, parsed}}
  rescue
    _ -> {:error, :bad_initiative}
  end

  # A set_initiative whose rolls are missing or not a list is a malformed
  # initiative, not an intent type the server does not know.
  defp decode_intent(%{"type" => "set_initiative"}, _pid), do: {:error, :bad_initiative}

  defp decode_intent(_payload, _pid), do: {:error, :unknown_intent}
end
