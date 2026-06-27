defmodule RoundtableWeb.Presence do
  @moduledoc "Tracks which players are currently connected to a table topic."
  use Phoenix.Presence, otp_app: :roundtable, pubsub_server: Roundtable.PubSub
end
