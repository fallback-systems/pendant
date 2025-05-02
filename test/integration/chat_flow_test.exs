defmodule Pendant.Integration.ChatFlowTest do
  use Pendant.ConnCase, async: false
  use Phoenix.ChannelTest
  
  alias Pendant.Chat
  
  @endpoint Pendant.Web.Endpoint
  
  setup do
    # Start CRDT registry and supervisor
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
  
  describe "complete chat flow" do
    test "full user journey through chat system" do
      # Step a1: Create two users
      {:ok, alice} = Chat.create_user(%{
        username: "alice_#{System.unique_integer([:positive])}",
        display_name: "Alice",
        device_id: "alice_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      {:ok, bob} = Chat.create_user(%{
        username: "bob_#{System.unique_integer([:positive])}",
        display_name: "Bob",
        device_id: "bob_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      # Step a2: Create tokens for both users
      alice_token = Pendant.Auth.generate_token(alice.id)
      bob_token = Pendant.Auth.generate_token(bob.id)
      
      # Step b1: Create a public room with CRDT enabled
      {:ok, room} = Chat.create_room(%{
        name: "integration_test_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test room for integration testing",
        crdt_enabled: true,
        crdt_type: "awset"
      })
      
      # Step b2: Add both users to the room
      {:ok, _} = Chat.add_user_to_room(alice.id, room.id, "admin")
      {:ok, _} = Chat.add_user_to_room(bob.id, room.id, "member")
      
      # Step c1: Connect sockets for both users
      {:ok, alice_socket} = connect(Pendant.Web.Socket, %{"token" => alice_token})
      {:ok, bob_socket} = connect(Pendant.Web.Socket, %{"token" => bob_token})
      
      # Step c2: Alice and Bob join the chat room
      {:ok, _, alice_chat_socket} = subscribe_and_join(
        alice_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{room.id}"
      )
      
      {:ok, _, bob_chat_socket} = subscribe_and_join(
        bob_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{room.id}"
      )
      
      # Step c3: Subscribe to the room to receive broadcasts
      Phoenix.PubSub.subscribe(Pendant.PubSub, "chat:room:#{room.id}")
      
      # Step d1: Alice sends a message
      alice_message = "Hello from Alice! #{System.unique_integer([:positive])}"
      ref = push(alice_chat_socket, "new_message", %{"content" => alice_message})
      assert_reply ref, :ok, alice_reply
      
      # Step d2: Bob should receive Alice's message
      assert_broadcast(:new_message, %{content: ^alice_message})
      
      # Step d3: Bob sends a reply
      bob_message = "Hello from Bob! #{System.unique_integer([:positive])}"
      ref = push(bob_chat_socket, "new_message", %{"content" => bob_message})
      assert_reply ref, :ok, bob_reply
      
      # Step d4: Alice should receive Bob's message
      assert_broadcast(:new_message, %{content: ^bob_message})
      
      # Step e1: Both users join the CRDT channel
      {:ok, _, alice_crdt_socket} = subscribe_and_join(
        alice_socket,
        Pendant.Web.ChatChannel,
        "crdt:#{room.id}"
      )
      
      {:ok, _, bob_crdt_socket} = subscribe_and_join(
        bob_socket,
        Pendant.Web.ChatChannel,
        "crdt:#{room.id}"
      )
      
      # Step e2: Subscribe to CRDT updates
      Phoenix.PubSub.subscribe(Pendant.PubSub, "crdt:#{room.id}")
      
      # Step e3: Alice adds an item to the CRDT
      alice_item = "item_from_alice_#{System.unique_integer([:positive])}"
      ref = push(alice_crdt_socket, "update_crdt", %{
        "operation" => %{"type" => "add", "key" => "items", "value" => alice_item}
      })
      assert_reply ref, :ok, alice_crdt_reply
      
      # Step e4: Check that the item was added
      assert alice_crdt_reply.crdt_data["items"] == alice_item
      
      # Step e5: Bob should receive the CRDT update
      assert_receive({:crdt_operation, _, _})
      
      # Step e6: Bob adds his own item
      bob_item = "item_from_bob_#{System.unique_integer([:positive])}"
      ref = push(bob_crdt_socket, "update_crdt", %{
        "operation" => %{"type" => "add", "key" => "items", "value" => bob_item}
      })
      assert_reply ref, :ok, bob_crdt_reply
      
      # Step e7: Check that Bob's item was added
      assert bob_crdt_reply.crdt_data["items"] == bob_item
      
      # Step e8: Alice should receive the CRDT update
      assert_receive({:crdt_operation, _, _})
      
      # Step f1: Check rate limiting by having Bob make many CRDT operations
      for i <- 1..7 do
        ref = push(bob_crdt_socket, "update_crdt", %{
          "operation" => %{"type" => "add", "key" => "items", "value" => "item_#{i}"}
        })
        
        if i <= 6 do
          assert_reply ref, :ok, _
        else
          # The 7th operation should be rate limited
          assert_reply ref, :error, %{reason: "rate_limited"}
        end
      end
      
      # Step g1: Both users leave the channels
      Process.unlink(Process.whereis(Pendant.Web.Endpoint))
      leave(alice_chat_socket)
      leave(bob_chat_socket)
      leave(alice_crdt_socket)
      leave(bob_crdt_socket)
    end
  end
end