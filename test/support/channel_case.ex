defmodule RoundtableWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by channel tests.

  Such tests rely on `Phoenix.ChannelTest` and import other functionality
  to make it easier to build common data structures and query the data layer.

  Finally, if the test case interacts with the database, we enable the SQL
  sandbox, so changes done to the database are reverted at the end of every
  test. (Not used here — the app is `--no-ecto`.)
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import RoundtableWeb.ChannelCase

      # The default endpoint for testing
      @endpoint RoundtableWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
