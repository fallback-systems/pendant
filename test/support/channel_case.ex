defmodule Pendant.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import Pendant.TestHelpers
      import Pendant.ChannelCase

      # The default endpoint for testing
      @endpoint Pendant.Web.Endpoint
    end
  end

  setup tags do
    Ecto.Adapters.SQL.Sandbox.checkout(Pendant.KnowledgeBase.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Pendant.KnowledgeBase.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  Setup helper that creates a socket with a authenticated user.
  """
  def setup_authenticated_socket(_context) do
    # Create test user
    user = Pendant.TestHelpers.create_test_user()
    
    # Generate token
    token = Pendant.Auth.generate_token(user.id)
    
    # Create socket with token
    {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
    
    {:ok, socket: socket, user: user, token: token}
  end
end