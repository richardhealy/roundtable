defmodule RoundtableWeb.SessionsDashboardPage do
  @moduledoc "LiveDashboard page listing active table sessions and their state."
  use Phoenix.LiveDashboard.PageBuilder

  @impl true
  def menu_link(_session, _capabilities), do: {:ok, "Sessions"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :rows, Roundtable.Telemetry.active_sessions())}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, assign(socket, :rows, Roundtable.Telemetry.active_sessions())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h5 class="card-title">Active sessions ({length(@rows)})</h5>
    <table class="table table-hover mt-0 dash-table">
      <thead>
        <tr>
          <th>Table</th>
          <th>Players</th>
          <th>Current turn</th>
          <th>Round</th>
          <th>Last seq</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td>{row.table_id}</td>
          <td>{row.players}</td>
          <td>{row.current || "—"}</td>
          <td>{row.round || "—"}</td>
          <td>{row.last_seq}</td>
        </tr>
      </tbody>
    </table>
    """
  end
end
