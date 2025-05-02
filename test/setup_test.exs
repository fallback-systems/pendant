defmodule Pendant.SetupTest do
  use ExUnit.Case
  
  test "test environment is properly set up" do
    # Test that the database is available
    assert Process.alive?(Process.whereis(Pendant.KnowledgeBase.Repo))
    
    # Test that we can create a user
    user = Pendant.TestHelpers.create_test_user(%{
      username: "setup_test_user",
      display_name: "Setup Test User"
    })
    
    assert user.id != nil
    assert user.username == "setup_test_user"
    
    # Test that we can create a room
    room = Pendant.TestHelpers.create_test_room(%{
      name: "setup_test_room",
      description: "Room for testing setup"
    })
    
    assert room.id != nil
    assert room.name == "setup_test_room"
    
    # Test that we can add a user to a room
    user_room = Pendant.TestHelpers.add_user_to_room(user, room)
    assert user_room != nil
    
    # Test that we can create a message
    message = Pendant.TestHelpers.create_test_message(user, room, %{
      content: "Setup test message"
    })
    
    assert message.id != nil
    assert message.content == "Setup test message"
    
    # Test that we can generate a token
    token = Pendant.TestHelpers.create_test_token(user)
    assert is_binary(token)
    assert String.length(token) > 0
    
    # Test token verification
    {:ok, decoded} = Pendant.Auth.verify_token(token)
    assert decoded.user_id == user.id
  end
end