defmodule Mix.Tasks.Roundtable.Token do
  @shortdoc "Mint a signed player token for local testing"
  @moduledoc """
  Print a signed token for a player id.

      mix roundtable.token amy
  """
  use Mix.Task

  @impl true
  def run([player_id]) do
    Mix.Task.run("app.start")
    Mix.shell().info(RoundtableWeb.UserSocket.sign(player_id))
  end

  def run(_), do: Mix.raise("usage: mix roundtable.token <player_id>")
end
