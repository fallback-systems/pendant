ExUnit.start(capture_log: true)

# Start the test database with test configuration
Application.put_env(:pendant, Pendant.KnowledgeBase.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "/home/user/dev/pendant/pendant_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10)

# Start the Repo
{:ok, _} = Pendant.KnowledgeBase.Repo.start_link([])

# Let's make sure our tables exist
Code.require_file("test/support/schema.ex")
# Drop existing tables and create fresh schema for tests
Pendant.Test.Schema.drop()
Pendant.Test.Schema.create()

# Start Phoenix endpoint for integration tests
Pendant.Web.Endpoint.start_link()

# Define mocks for external dependencies if needed
# We'll use integration tests for the full system

# Use the repo's sandbox mode for concurrent tests
Ecto.Adapters.SQL.Sandbox.mode(Pendant.KnowledgeBase.Repo, :manual)

defmodule Pendant.TestHelpers do
  @moduledoc """
  Helper functions for tests.
  """
  
  alias Pendant.KnowledgeBase.Repo
  alias Pendant.Chat.{User, Room, Message, UserRoom}
  
  @doc """
  Creates a user for tests.
  """
  def create_test_user(attrs \\ %{}) do
    {:ok, user} = 
      attrs
      |> Enum.into(%{
        username: "test_user_#{System.unique_integer([:positive])}",
        display_name: "Test User",
        device_id: "test_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      |> Pendant.Chat.create_user()
      
    user
  end
  
  @doc """
  Creates a room for tests.
  """
  def create_test_room(attrs \\ %{}) do
    {:ok, room} =
      attrs
      |> Enum.into(%{
        name: "test_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test room description",
        crdt_enabled: false
      })
      |> Pendant.Chat.create_room()
      
    room
  end
  
  @doc """
  Creates a CRDT-enabled room for tests.
  """
  def create_test_crdt_room(attrs \\ %{}) do
    {:ok, room} =
      attrs
      |> Enum.into(%{
        name: "test_crdt_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test CRDT room",
        crdt_enabled: true,
        crdt_type: "awset"
      })
      |> Pendant.Chat.create_room()
      
    room
  end
  
  @doc """
  Adds a user to a room for tests.
  """
  def add_user_to_room(user, room, role \\ "member") do
    {:ok, user_room} = Pendant.Chat.add_user_to_room(user.id, room.id, role)
    user_room
  end
  
  @doc """
  Creates a message for tests.
  """
  def create_test_message(user, room, attrs \\ %{}) do
    {:ok, message} =
      attrs
      |> Enum.into(%{
        content: "Test message content #{System.unique_integer([:positive])}",
        message_type: "text",
        user_id: user.id,
        room_id: room.id
      })
      |> Pendant.Chat.create_message()
      
    message
  end
  
  @doc """
  Creates a token for tests.
  """
  def create_test_token(user) do
    Pendant.Auth.generate_token(user.id)
  end
end
