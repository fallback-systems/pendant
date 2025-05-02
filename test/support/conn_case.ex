defmodule Pendant.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Pendant.TestHelpers
      import Pendant.ConnCase

      alias Pendant.Web.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint Pendant.Web.Endpoint
    end
  end

  setup tags do
    Ecto.Adapters.SQL.Sandbox.checkout(Pendant.KnowledgeBase.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Pendant.KnowledgeBase.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that creates a user and authenticates the connection.
  """
  def setup_authenticated_conn(_context) do
    # Create test user
    user = Pendant.TestHelpers.create_test_user()
    
    # Generate token
    token = Pendant.Auth.generate_token(user.id)
    
    # Create authenticated connection
    conn = Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    
    {:ok, conn: conn, user: user, token: token}
  end
end