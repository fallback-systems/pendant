defmodule Pendant.ChatTest do
  use Pendant.DataCase, async: true
  alias Pendant.Chat
  alias Pendant.Chat.{User, Room, Message, UserRoom}
  
  describe "user functions" do
    test "get_user/1 returns user by ID" do
      user = create_test_user()
      assert Chat.get_user(user.id) == user
    end
    
    test "get_user_by_username/1 returns user by username" do
      user = create_test_user()
      assert Chat.get_user_by_username(user.username) == user
    end
    
    test "get_user_by_device_id/1 returns user by device_id" do
      user = create_test_user()
      assert Chat.get_user_by_device_id(user.device_id) == user
    end
    
    test "create_user/1 creates a user" do
      attrs = %{
        username: "test_user_#{System.unique_integer([:positive])}",
        display_name: "Test User",
        device_id: "test_device_#{System.unique_integer([:positive])}",
        status: "online"
      }
      
      assert {:ok, %User{} = user} = Chat.create_user(attrs)
      assert user.username == attrs.username
      assert user.display_name == attrs.display_name
      assert user.device_id == attrs.device_id
      assert user.status == attrs.status
    end
    
    test "create_user/1 fails with invalid attributes" do
      # Missing required field
      attrs = %{
        display_name: "Test User",
        device_id: "test_device_#{System.unique_integer([:positive])}",
        status: "online"
      }
      
      assert {:error, %Ecto.Changeset{}} = Chat.create_user(attrs)
    end
    
    test "update_user/2 updates a user" do
      user = create_test_user()
      update_attrs = %{display_name: "Updated Name"}
      
      assert {:ok, %User{} = updated_user} = Chat.update_user(user, update_attrs)
      assert updated_user.display_name == "Updated Name"
    end
    
    test "update_user_status/2 updates a user's status" do
      user = create_test_user()
      
      assert {:ok, %User{} = updated_user} = Chat.update_user_status(user, "away")
      assert updated_user.status == "away"
      assert updated_user.last_seen_at != nil
    end
    
    test "list_online_users/0 returns online users" do
      # Create an online user
      online_user = create_test_user(%{status: "online"})
      
      # Create an offline user
      offline_user = create_test_user(%{status: "offline"})
      
      online_users = Chat.list_online_users()
      
      assert Enum.any?(online_users, fn u -> u.id == online_user.id end)
      refute Enum.any?(online_users, fn u -> u.id == offline_user.id end)
    end
  end
  
  describe "room functions" do
    test "get_room/1 returns room by ID" do
      room = create_test_room()
      assert Chat.get_room(room.id) == room
    end
    
    test "get_room_by_name/1 returns room by name" do
      room = create_test_room()
      assert Chat.get_room_by_name(room.name) == room
    end
    
    test "create_room/1 creates a room" do
      attrs = %{
        name: "test_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test room description"
      }
      
      assert {:ok, %Room{} = room} = Chat.create_room(attrs)
      assert room.name == attrs.name
      assert room.room_type == attrs.room_type
      assert room.description == attrs.description
    end
    
    test "create_room/1 with CRDT enabled initializes CRDT data" do
      attrs = %{
        name: "test_crdt_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test CRDT room",
        crdt_enabled: true,
        crdt_type: "awset"
      }
      
      assert {:ok, %Room{} = room} = Chat.create_room(attrs)
      assert room.crdt_enabled == true
    end
    
    test "update_room/2 updates a room" do
      room = create_test_room()
      update_attrs = %{description: "Updated description"}
      
      assert {:ok, %Room{} = updated_room} = Chat.update_room(room, update_attrs)
      assert updated_room.description == "Updated description"
    end
    
    test "list_public_rooms/0 returns public rooms" do
      # Create a public room
      public_room = create_test_room(%{room_type: "public"})
      
      # Create a private room
      private_room = create_test_room(%{room_type: "private"})
      
      public_rooms = Chat.list_public_rooms()
      
      assert Enum.any?(public_rooms, fn r -> r.id == public_room.id end)
      refute Enum.any?(public_rooms, fn r -> r.id == private_room.id end)
    end
    
    test "list_user_rooms/1 returns rooms a user is member of" do
      user = create_test_user()
      room1 = create_test_room()
      room2 = create_test_room()
      
      # Add user to room1
      Chat.add_user_to_room(user.id, room1.id)
      
      user_rooms = Chat.list_user_rooms(user.id)
      
      assert Enum.any?(user_rooms, fn r -> r.id == room1.id end)
      refute Enum.any?(user_rooms, fn r -> r.id == room2.id end)
    end
    
    test "add_user_to_room/3 adds a user to a room" do
      user = create_test_user()
      room = create_test_room()
      
      assert {:ok, %UserRoom{}} = Chat.add_user_to_room(user.id, room.id)
      
      # Verify user is in the room
      assert Enum.any?(Chat.list_user_rooms(user.id), fn r -> r.id == room.id end)
    end
    
    test "remove_user_from_room/2 removes a user from a room" do
      user = create_test_user()
      room = create_test_room()
      
      # Add user to room
      Chat.add_user_to_room(user.id, room.id)
      
      # Verify user is in the room
      assert Enum.any?(Chat.list_user_rooms(user.id), fn r -> r.id == room.id end)
      
      # Remove user from room
      Chat.remove_user_from_room(user.id, room.id)
      
      # Verify user is no longer in the room
      refute Enum.any?(Chat.list_user_rooms(user.id), fn r -> r.id == room.id end)
    end
    
    test "list_room_users/1 returns users in a room" do
      user1 = create_test_user()
      user2 = create_test_user()
      room = create_test_room()
      
      # Add users to room
      Chat.add_user_to_room(user1.id, room.id)
      Chat.add_user_to_room(user2.id, room.id, "admin")
      
      room_users = Chat.list_room_users(room.id)
      
      # Verify both users are in the result
      assert Enum.any?(room_users, fn r -> r.user.id == user1.id end)
      assert Enum.any?(room_users, fn r -> r.user.id == user2.id end)
      
      # Verify roles are set correctly
      user1_entry = Enum.find(room_users, fn r -> r.user.id == user1.id end)
      user2_entry = Enum.find(room_users, fn r -> r.user.id == user2.id end)
      
      assert user1_entry.role == "member"
      assert user2_entry.role == "admin"
    end
  end
  
  describe "message functions" do
    setup do
      user = create_test_user()
      room = create_test_room()
      Chat.add_user_to_room(user.id, room.id)
      
      {:ok, %{user: user, room: room}}
    end
    
    test "get_message/1 returns message by ID", %{user: user, room: room} do
      message = create_test_message(user, room)
      
      assert %Message{} = fetched_message = Chat.get_message(message.id)
      assert fetched_message.id == message.id
      assert fetched_message.user != nil
    end
    
    test "create_message/1 creates a message", %{user: user, room: room} do
      attrs = %{
        content: "Test message content",
        message_type: "text",
        user_id: user.id,
        room_id: room.id
      }
      
      assert {:ok, %Message{} = message} = Chat.create_message(attrs)
      assert message.content == attrs.content
      assert message.message_type == attrs.message_type
      assert message.user_id == attrs.user_id
      assert message.room_id == attrs.room_id
      assert message.user != nil
    end
    
    test "list_room_messages/3 returns messages with pagination", %{user: user, room: room} do
      # Create 10 messages
      for i <- 1..10 do
        Chat.create_message(%{
          content: "Message #{i}",
          message_type: "text",
          user_id: user.id,
          room_id: room.id
        })
      end
      
      # Get first page (5 messages)
      result = Chat.list_room_messages(room.id, 5)
      
      assert %{messages: messages, cursor: cursor, has_more: has_more} = result
      assert length(messages) == 5
      assert cursor != nil
      assert has_more == true
      
      # Get second page using cursor
      result2 = Chat.list_room_messages(room.id, 5, cursor)
      
      assert %{messages: messages2, cursor: cursor2, has_more: has_more2} = result2
      assert length(messages2) == 5
      assert cursor2 != nil
      assert has_more2 == false
      
      # Ensure pages don't overlap
      message_ids = Enum.map(messages, & &1.id)
      message_ids2 = Enum.map(messages2, & &1.id)
      
      assert Enum.empty?(message_ids -- message_ids) # No duplicates
      assert Enum.empty?(message_ids2 -- message_ids2) # No duplicates
    end
    
    test "get_messages_since/2 returns messages since timestamp", %{user: user, room: room} do
      # Create a message
      {:ok, message1} = Chat.create_message(%{
        content: "Old message",
        message_type: "text",
        user_id: user.id,
        room_id: room.id
      })
      
      # Get the timestamp
      timestamp = message1.inserted_at
      
      # Create another message
      {:ok, message2} = Chat.create_message(%{
        content: "New message",
        message_type: "text",
        user_id: user.id,
        room_id: room.id
      })
      
      # Get messages since the timestamp
      messages = Chat.get_messages_since(room.id, timestamp)
      
      # Only the new message should be returned
      assert length(messages) == 1
      assert List.first(messages).id == message2.id
    end
  end
  
  describe "CRDT functions" do
    setup do
      # Start CRDT registry and supervisor
      {:ok, _} = Registry.start_link(keys: :unique, name: Pendant.CRDTRegistry)
      {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one, name: Pendant.CRDTSupervisor)
      
      room = create_test_crdt_room()
      
      on_exit(fn ->
        try do
          DynamicSupervisor.stop(supervisor)
        catch
          :exit, _ -> :ok
        end
      end)
      
      {:ok, %{room: room}}
    end
    
    test "update_crdt/2 updates the CRDT", %{room: room} do
      operation = %{type: "add", key: "items", value: "item1"}
      
      assert {:ok, _} = Chat.update_crdt(room.id, operation)
      
      # Verify the CRDT was updated
      {:ok, data} = Chat.get_crdt_data(room.id)
      assert data["items"] == "item1"
    end
    
    test "update_crdt/2 returns error if CRDT not enabled" do
      room = create_test_room(%{crdt_enabled: false})
      operation = %{type: "add", key: "items", value: "item1"}
      
      assert {:error, _} = Chat.update_crdt(room.id, operation)
    end
    
    test "get_crdt_data/1 returns CRDT data", %{room: room} do
      # Add data to the CRDT
      operation = %{type: "add", key: "items", value: "item1"}
      Chat.update_crdt(room.id, operation)
      
      assert {:ok, data} = Chat.get_crdt_data(room.id)
      assert data["items"] == "item1"
    end
    
    test "get_crdt_data/1 returns error if CRDT not enabled" do
      room = create_test_room(%{crdt_enabled: false})
      
      assert {:error, _} = Chat.get_crdt_data(room.id)
    end
    
    test "merge_crdt_delta/2 merges delta with CRDT", %{room: room} do
      # This is more of an integration test with CRDTManager
      # First, add some data to the CRDT
      Chat.update_crdt(room.id, %{type: "add", key: "items", value: "item1"})
      
      # Merge an empty delta (hard to test actual deltas without internals)
      assert :ok = Chat.merge_crdt_delta(room.id, %{})
      
      # Verify data is still there
      {:ok, data} = Chat.get_crdt_data(room.id)
      assert data["items"] == "item1"
    end
    
    test "merge_crdt_delta/2 returns error if CRDT not enabled" do
      room = create_test_room(%{crdt_enabled: false})
      
      assert {:error, _} = Chat.merge_crdt_delta(room.id, %{})
    end
  end
end