defmodule RoundtableWeb.UserSocket do
  @moduledoc "Socket entrypoint. Authenticates a signed token into a player_id."
  use Phoenix.Socket

  channel "table:*", RoundtableWeb.TableChannel

  @salt "player auth"
  @max_age 86_400

  @doc "Sign a player token (used by the dev mix task and tests)."
  @spec sign(term()) :: String.t()
  def sign(player_id) do
    Phoenix.Token.sign(RoundtableWeb.Endpoint, @salt, player_id)
  end

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(RoundtableWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, player_id} -> {:ok, assign(socket, :player_id, player_id)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "player_socket:#{socket.assigns.player_id}"
end
