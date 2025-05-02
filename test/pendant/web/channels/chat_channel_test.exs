defmodule Pendant.Web.ChatChannelTest do
  use Pendant.ChannelCase, async: false
  alias Pendant.Web.ChatChannel
  alias Pendant.KnowledgeBase.Repo
  
  # Setup for CRDT registry and supervisor
  setup do
    # Start registry and supervisor for CRDT tests
    {:ok, _} = Registry.start_link(keys: :unique, name: Pendant.CRDTRegistry)
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one, name: Pendant.CRDTSupervisor)
    
    # Start the rate limiter
    {:ok, rate_limiter} = Pendant.RateLimiter.start_link([])
    
    on_exit(fn ->
      # Clean up processes
      try do
        DynamicSupervisor.stop(supervisor)
        Process.exit(rate_limiter, :normal)
      catch
        :exit, _ -> :ok
      end
    end)
    
    :ok
  end
  
  describe "join/3 for chat:room" do
    setup do
      # Create test user and room
      user = create_test_user()
      room = create_test_room()
      
      # Add user to room
      add_user_to_room(user, room)
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      {:ok, %{
        user: user,
        room: room,
        socket: socket,
        token: token
      }}
    end
    
    test "successfully joins a room the user is a member of", %{socket: socket, room: room} do
      assert {:ok, reply, channel_socket} = 
        subscribe_and_join(socket, ChatChannel, "chat:room:#{room.id}")
      
      # Check that reply contains required data
      assert Map.has_key?(reply, :messages)
      assert Map.has_key?(reply, :room)
      assert Map.has_key?(reply, :users)
      
      # Check that socket has room_id assigned
      assert channel_socket.assigns.room_id == room.id
    end
    
    test "rejects joining a room the user is not a member of", %{socket: socket} do
      # Create a room the user is not a member of
      other_room = create_test_room()
      
      assert {:error, %{reason: "unauthorized"}} = 
        subscribe_and_join(socket, ChatChannel, "chat:room:#{other_room.id}")
    end
    
    test "handles error when trying to join with invalid room id", %{socket: socket} do
      assert {:error, %{reason: "server_error"}} = 
        subscribe_and_join(socket, ChatChannel, "chat:room:invalid_id")
    end
  end
  
  describe "join/3 for chat:lobby" do
    setup do
      # Create test user
      user = create_test_user()
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      {:ok, %{user: user, socket: socket, token: token}}
    end
    
    test "successfully joins the lobby", %{socket: socket} do
      assert {:ok, _reply, _socket} = 
        subscribe_and_join(socket, ChatChannel, "chat:lobby")
    end
  end
  
  describe "join/3 for chat:direct" do
    setup do
      # Create test users
      user1 = create_test_user()
      user2 = create_test_user()
      
      # Generate token and connect socket for user1
      token = create_test_token(user1)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      {:ok, %{user1: user1, user2: user2, socket: socket, token: token}}
    end
    
    test "redirects to a room when starting direct chat", %{socket: socket, user2: user2} do
      assert {:error, %{reason: "redirect", room_id: room_id}} = 
        subscribe_and_join(socket, ChatChannel, "chat:direct:#{user2.id}")
      
      # Verify a room was created
      assert is_integer(room_id)
      room = Pendant.Chat.get_room(room_id)
      assert room.room_type == "direct"
    end
    
    test "rejects direct chat with self", %{socket: socket, user1: user1} do
      assert {:error, %{reason: "cannot chat with yourself"}} = 
        subscribe_and_join(socket, ChatChannel, "chat:direct:#{user1.id}")
    end
  end
  
  describe "join/3 for crdt topics" do
    setup do
      # Create test user and CRDT room
      user = create_test_user()
      room = create_test_crdt_room()
      
      # Add user to room
      add_user_to_room(user, room)
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      {:ok, %{
        user: user,
        room: room,
        socket: socket,
        token: token
      }}
    end
    
    test "successfully joins a CRDT channel for a room", %{socket: socket, room: room} do
      assert {:ok, reply, channel_socket} = 
        subscribe_and_join(socket, ChatChannel, "crdt:#{room.id}")
      
      # Check that reply contains CRDT data
      assert Map.has_key?(reply, :crdt_data)
      
      # Check that socket has room_id assigned
      assert channel_socket.assigns.room_id == room.id
    end
    
    test "rejects joining a CRDT channel for a room the user is not a member of", %{socket: socket} do
      # Create a room the user is not a member of
      other_room = create_test_crdt_room()
      
      assert {:error, %{reason: "unauthorized"}} = 
        subscribe_and_join(socket, ChatChannel, "crdt:#{other_room.id}")
    end
  end
  
  describe "handle_in for new_message" do
    setup do
      # Create test user and room
      user = create_test_user()
      room = create_test_room()
      
      # Add user to room
      add_user_to_room(user, room)
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Join the room channel
      {:ok, _reply, channel_socket} = 
        subscribe_and_join(socket, ChatChannel, "chat:room:#{room.id}")
      
      {:ok, %{
        user: user,
        room: room,
        socket: socket,
        channel_socket: channel_socket
      }}
    end
    
    test "creates a new message", %{channel_socket: channel_socket} do
      # Push a new message
      content = "Test message #{System.unique_integer([:positive])}"
      ref = push(channel_socket, "new_message", %{"content" => content})
      
      # Wait for reply
      assert_reply ref, :ok, reply
      
      # Check reply
      assert Map.has_key?(reply, :id)
      assert reply.content == content
      assert reply.message_type == "text"
    end
    
    test "broadcasts the new message to all subscribers", %{channel_socket: channel_socket, room: room} do
      # Subscribe to the room's PubSub topic
      Phoenix.PubSub.subscribe(Pendant.PubSub, "chat:room:#{room.id}")
      
      # Push a new message
      content = "Broadcast test #{System.unique_integer([:positive])}"
      push(channel_socket, "new_message", %{"content" => content})
      
      # Wait for the broadcast
      assert_broadcast(:new_message, %{content: ^content})
    end
    
    test "returns error for invalid message", %{channel_socket: channel_socket} do
      # Push an invalid message (empty content)
      ref = push(channel_socket, "new_message", %{"content" => ""})
      
      # Should get an error reply
      assert_reply ref, :error, %{errors: errors}
      assert errors != %{}
    end
  end
  
  describe "handle_in for update_crdt" do
    setup do
      # Create test user and CRDT room
      user = create_test_user()
      room = create_test_crdt_room()
      
      # Add user to room
      add_user_to_room(user, room)
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Join the CRDT channel
      {:ok, _reply, channel_socket} = 
        subscribe_and_join(socket, ChatChannel, "crdt:#{room.id}")
      
      {:ok, %{
        user: user,
        room: room,
        socket: socket,
        channel_socket: channel_socket
      }}
    end
    
    test "updates the CRDT", %{channel_socket: channel_socket} do
      # Push a CRDT update
      operation = %{"type" => "add", "key" => "items", "value" => "item1"}
      ref = push(channel_socket, "update_crdt", %{"operation" => operation})
      
      # Wait for reply
      assert_reply ref, :ok, reply
      
      # Check reply
      assert Map.has_key?(reply, :crdt_data)
      assert Map.has_key?(reply, :updated_value)
      assert Map.has_key?(reply, :rate_limit)
      
      # Check that the CRDT was updated
      assert reply.crdt_data["items"] == "item1"
      assert reply.updated_value == "item1"
    end
    
    test "broadcasts the CRDT update to all subscribers", %{channel_socket: channel_socket, room: room} do
      # Subscribe to the CRDT's PubSub topic
      Phoenix.PubSub.subscribe(Pendant.PubSub, "crdt:#{room.id}")
      
      # Push a CRDT update
      operation = %{"type" => "add", "key" => "items", "value" => "item1"}
      push(channel_socket, "update_crdt", %{"operation" => operation})
      
      # Wait for the broadcast
      assert_receive({:crdt_operation, _, _})
    end
    
    test "respects rate limiting", %{channel_socket: channel_socket} do
      # Push CRDT updates until rate limited
      # The default bucket has 20 tokens and each CRDT update costs 3
      # So we should be able to do 6 operations before being rate limited
      
      # Make 6 operations
      for i <- 1..6 do
        operation = %{"type" => "add", "key" => "items", "value" => "item#{i}"}
        ref = push(channel_socket, "update_crdt", %{"operation" => operation})
        assert_reply ref, :ok, _
      end
      
      # The 7th operation should be rate limited
      operation = %{"type" => "add", "key" => "items", "value" => "rate_limited_item"}
      ref = push(channel_socket, "update_crdt", %{"operation" => operation})
      
      # Should get a rate limited error
      assert_reply ref, :error, %{reason: "rate_limited", retry_after: retry_after}
      assert is_integer(retry_after)
    end
    
    test "rejects unauthorized CRDT updates", %{user: user, room: room} do
      # Create another user
      other_user = create_test_user()
      
      # Generate token and connect socket for the other user
      other_token = create_test_token(other_user)
      {:ok, other_socket} = connect(Pendant.Web.Socket, %{"token" => other_token})
      
      # The other user shouldn't be able to join the CRDT channel
      assert {:error, %{reason: "unauthorized"}} = 
        subscribe_and_join(other_socket, ChatChannel, "crdt:#{room.id}")
    end
  end
  
  describe "handle_in for typing" do
    setup do
      # Create test user and room
      user = create_test_user()
      room = create_test_room()
      
      # Add user to room
      add_user_to_room(user, room)
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Join the room channel
      {:ok, _reply, channel_socket} = 
        subscribe_and_join(socket, ChatChannel, "chat:room:#{room.id}")
      
      {:ok, %{
        user: user,
        room: room,
        socket: socket,
        channel_socket: channel_socket
      }}
    end
    
    test "broadcasts typing event", %{channel_socket: channel_socket, user: user} do
      # Subscribe to the same channel
      subscribe_and_join(socket, ChatChannel, "chat:room:#{channel_socket.assigns.room_id}")
      
      # Push typing event
      push(channel_socket, "typing", %{})
      
      # Should broadcast typing event to others (excluding sender)
      assert_broadcast("user_typing", %{user_id: user_id})
      assert user_id == user.id
    end
  end
  
  describe "handle_in for get_messages_since" do
    setup do
      # Create test user and room
      user = create_test_user()
      room = create_test_room()
      
      # Add user to room
      add_user_to_room(user, room)
      
      # Create some messages
      message1 = create_test_message(user, room)
      Process.sleep(100) # Ensure different timestamps
      message2 = create_test_message(user, room)
      
      # Generate token and connect socket
      token = create_test_token(user)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Join the room channel
      {:ok, _reply, channel_socket} = 
        subscribe_and_join(socket, ChatChannel, "chat:room:#{room.id}")
      
      {:ok, %{
        user: user,
        room: room,
        messages: [message1, message2],
        socket: socket,
        channel_socket: channel_socket
      }}
    end
    
    test "returns messages since timestamp", %{channel_socket: channel_socket, messages: [message1, _]} do
      # Get messages since the first message
      since = DateTime.to_iso8601(message1.inserted_at)
      ref = push(channel_socket, "get_messages_since", %{"since" => since})
      
      # Should get a reply with the second message
      assert_reply ref, :ok, %{messages: messages}
      assert length(messages) == 1
    end
    
    test "handles invalid timestamp", %{channel_socket: channel_socket} do
      # Push with invalid timestamp
      ref = push(channel_socket, "get_messages_since", %{"since" => "invalid"})
      
      # Should get an error
      assert_reply ref, :error, %{reason: "Invalid timestamp format"}
    end
  end
end