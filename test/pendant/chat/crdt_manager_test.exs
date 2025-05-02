defmodule Pendant.Chat.CRDTManagerTest do
  use Pendant.DataCase, async: false
  alias Pendant.Chat.CRDTManager
  
  setup do
    # Create a CRDT-enabled room for testing
    room = create_test_crdt_room()
    
    # Start a registry for testing
    {:ok, _} = Registry.start_link(keys: :unique, name: Pendant.CRDTRegistry)
    
    # Start a supervisor for the CRDT managers
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one, name: Pendant.CRDTSupervisor)
    
    on_exit(fn ->
      # Clean up after each test
      try do
        DynamicSupervisor.stop(supervisor)
      catch
        :exit, _ -> :ok
      end
    end)
    
    {:ok, %{room: room}}
  end
  
  describe "start_link/1" do
    test "starts a CRDT manager for a room", %{room: room} do
      assert {:ok, pid} = CRDTManager.start_link(room.id)
      assert Process.alive?(pid)
    end
    
    test "returns an error for non-existent room" do
      assert {:error, _} = CRDTManager.start_link(999_999)
    end
    
    test "returns an error if CRDT is not enabled for the room" do
      # Create a room with CRDT disabled
      {:ok, room} = Pendant.Chat.create_room(%{
        name: "test_room_no_crdt",
        room_type: "public",
        description: "Test room without CRDT",
        crdt_enabled: false
      })
      
      assert {:error, _} = CRDTManager.start_link(room.id)
    end
  end
  
  describe "get_crdt_data/1" do
    test "returns empty map for a new CRDT", %{room: room} do
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data == %{}
    end
    
    test "returns error for non-existent room" do
      assert {:error, _} = CRDTManager.get_crdt_data(999_999)
    end
  end
  
  describe "update_crdt/2" do
    test "adds an item to a set", %{room: room} do
      operation = %{type: "add", key: "items", value: "item1"}
      
      assert {:ok, "item1"} = CRDTManager.update_crdt(room.id, operation)
      
      # Check that the item is in the CRDT
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["items"] == "item1"
    end
    
    test "sets a value with set operation", %{room: room} do
      operation = %{type: "set", key: "title", value: "New Title"}
      
      assert {:ok, "New Title"} = CRDTManager.update_crdt(room.id, operation)
      
      # Check that the value is set in the CRDT
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["title"] == "New Title"
    end
    
    test "increments a counter", %{room: room} do
      # First, set the initial value to 0
      CRDTManager.update_crdt(room.id, %{type: "set", key: "counter", value: 0})
      
      # Now increment it
      operation = %{type: "increment", key: "counter"}
      
      assert {:ok, 1} = CRDTManager.update_crdt(room.id, operation)
      
      # Check that the counter is incremented
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["counter"] == 1
    end
    
    test "decrements a counter", %{room: room} do
      # First, set the initial value to 5
      CRDTManager.update_crdt(room.id, %{type: "set", key: "counter", value: 5})
      
      # Now decrement it
      operation = %{type: "decrement", key: "counter"}
      
      assert {:ok, 4} = CRDTManager.update_crdt(room.id, operation)
      
      # Check that the counter is decremented
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["counter"] == 4
    end
    
    test "updates a map", %{room: room} do
      # First, set an initial map
      CRDTManager.update_crdt(room.id, %{type: "set", key: "config", value: %{"theme" => "light"}})
      
      # Now update a field in the map
      operation = %{type: "update", key: "config", nested_key: "theme", value: "dark"}
      
      assert {:ok, %{"theme" => "dark"}} = CRDTManager.update_crdt(room.id, operation)
      
      # Check that the map is updated
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["config"]["theme"] == "dark"
    end
    
    test "returns error for unknown operation type", %{room: room} do
      operation = %{type: "unknown_type", key: "items", value: "item1"}
      
      assert {:error, :unknown_operation} = CRDTManager.update_crdt(room.id, operation)
    end
    
    test "returns error for non-existent room" do
      operation = %{type: "add", key: "items", value: "item1"}
      
      assert {:error, _} = CRDTManager.update_crdt(999_999, operation)
    end
    
    test "handles multiple operations in sequence", %{room: room} do
      # Add an item
      CRDTManager.update_crdt(room.id, %{type: "add", key: "items", value: "item1"})
      
      # Set a title
      CRDTManager.update_crdt(room.id, %{type: "set", key: "title", value: "Test Title"})
      
      # Create and update a map
      CRDTManager.update_crdt(room.id, %{type: "set", key: "config", value: %{"theme" => "light"}})
      CRDTManager.update_crdt(room.id, %{type: "update", key: "config", nested_key: "language", value: "en"})
      
      # Check that all operations have been applied
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["items"] == "item1"
      assert data["title"] == "Test Title"
      assert data["config"]["theme"] == "light"
      assert data["config"]["language"] == "en"
    end
  end
  
  describe "merge_delta/2" do
    test "successfully merges a delta", %{room: room} do
      # This is hard to test directly because we don't have direct access to deltas
      # We'll test it indirectly using the CRDT API
      
      # Add an item
      CRDTManager.update_crdt(room.id, %{type: "add", key: "items", value: "item1"})
      
      # Get the CRDT data, which confirms the delta was successfully applied
      {:ok, data} = CRDTManager.get_crdt_data(room.id)
      assert data["items"] == "item1"
      
      # Attempt to merge an empty delta (this should succeed but not change anything)
      assert :ok = CRDTManager.merge_delta(room.id, %{})
      
      # Data should be unchanged
      {:ok, data_after} = CRDTManager.get_crdt_data(room.id)
      assert data_after == data
    end
    
    test "returns error for non-existent room" do
      assert {:error, _} = CRDTManager.merge_delta(999_999, %{})
    end
  end
  
  # Test to verify the CRDT state is saved to the database
  # This test is inherently timing-dependent, which is not ideal,
  # but is necessary to test the persistence behavior
  test "saves CRDT state to database", %{room: room} do
    # Add an item
    CRDTManager.update_crdt(room.id, %{type: "add", key: "items", value: "item1"})
    
    # Wait for the save_to_db handler to run
    # This is typically called every PROPAGATE_INTERVAL * 2 milliseconds
    Process.sleep(10_000)
    
    # Reload the room from the database
    updated_room = Pendant.Chat.get_room(room.id)
    
    # The CRDT data should be saved in the database
    assert updated_room.crdt_data != %{}
    assert updated_room.crdt_data["items"] == "item1"
  end
end