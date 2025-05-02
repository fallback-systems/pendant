defmodule Pendant.Chat.CRDTManager do
  @moduledoc """
  Manages Conflict-free Replicated Data Types (CRDTs) for the chat system.
  
  Uses the delta_crdt library which implements Delta-State CRDTs for:
  - Add-Wins Set (AWSet)
  - Remove-Wins Set (RWSet)
  - Grow-Only Counter (GCounter)
  - Positive-Negative Counter (PNCounter)
  - Multi-Value Register (MVRegister)
  - Last-Write-Wins Register (LWWRegister)
  - Observed-Remove Map (ORMap)
  - Add-Wins Map (AWMap)
  
  These data structures allow for conflict-free merging of data even
  when updates happen concurrently and independently, while only transmitting
  delta states for efficiency.
  """
  
  use GenServer
  require Logger
  
  alias DeltaCrdt.{CausalCrdt, AWLWWMap}
  alias Pendant.Chat.Room
  alias Pendant.KnowledgeBase.Repo

  # Time to wait before propagating changes
  @propagate_interval 5_000
  
  # Public API
  
  @doc """
  Start a CRDT manager process for a specific room.
  """
  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end
  
  @doc """
  Get the CRDT data for a room.
  """
  def get_crdt_data(room_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_data)
        
      {:error, _} = error ->
        error
    end
  end
  
  @doc """
  Update the CRDT with a new operation.
  
  Operations are maps with the following structure:
  
  For AWSet:
  %{type: "add", key: "items", value: item}
  %{type: "remove", key: "items", value: item}
  
  For LWWRegister:
  %{type: "set", key: "title", value: "New Title"}
  
  For PNCounter:
  %{type: "increment", key: "counter"}
  %{type: "decrement", key: "counter"}
  
  For ORMap:
  %{type: "update", key: "map", nested_key: "field", value: "value"}
  """
  def update_crdt(room_id, operation) do
    case lookup(room_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:update, operation})
        
      {:error, _} = error ->
        error
    end
  end
  
  @doc """
  Merge a remote CRDT delta with the local CRDT.
  """
  def merge_delta(room_id, delta) do
    case lookup(room_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:merge_delta, delta})
        
      {:error, _} = error ->
        error
    end
  end
  
  # GenServer callbacks
  
  @impl true
  def init(room_id) do
    # Get the room to confirm it exists and is CRDT-enabled
    case Repo.get(Room, room_id) do
      nil ->
        {:stop, {:error, :room_not_found}}
        
      %{crdt_enabled: false} ->
        {:stop, {:error, :crdt_not_enabled}}
        
      room ->
        # Initialize the CRDT node name
        node_name = generate_node_name(room_id)
        
        # Start the CRDT process
        {:ok, crdt} = DeltaCrdt.start_link(AWLWWMap, sync_interval: @propagate_interval)
        
        # Load existing CRDT data from database if it exists
        if room.crdt_data && map_size(room.crdt_data) > 0 do
          load_crdt_from_db(crdt, room.crdt_data)
        end
        
        # Subscribe to CRDT changes
        DeltaCrdt.subscribe(crdt, self())
        
        # Schedule periodic saving to database
        Process.send_after(self(), :save_to_db, @propagate_interval * 2)
        
        state = %{
          room_id: room_id,
          room: room,
          crdt: crdt,
          node_name: node_name,
          dirty: false,
          last_saved: DateTime.utc_now()
        }
        
        {:ok, state}
    end
  end
  
  @impl true
  def handle_call(:get_data, _from, state) do
    data = DeltaCrdt.to_map(state.crdt)
    {:reply, {:ok, data}, state}
  end
  
  @impl true
  def handle_call({:update, operation}, _from, state) do
    # Apply the operation to the CRDT
    result = apply_operation(state.crdt, operation)
    
    # Broadcast the update
    broadcast_change(state.room_id, operation)
    
    # Mark state as dirty for future save
    {:reply, result, %{state | dirty: true}}
  end
  
  @impl true
  def handle_cast({:merge_delta, delta}, state) do
    # Apply the delta to our CRDT
    :ok = DeltaCrdt.merge(state.crdt, delta)
    
    # Mark state as dirty
    {:noreply, %{state | dirty: true}}
  end
  
  @impl true
  def handle_info({:crdt_update, delta}, state) do
    # A local change occurred, broadcast it for P2P syncing
    broadcast_delta(state.room_id, delta)
    
    # Mark state as dirty
    {:noreply, %{state | dirty: true}}
  end
  
  @impl true
  def handle_info(:save_to_db, state) do
    new_state = if state.dirty do
      # Get current CRDT state
      crdt_data = DeltaCrdt.to_map(state.crdt)
      
      # Update the database
      Repo.get(Room, state.room_id)
      |> Ecto.Changeset.change(%{crdt_data: crdt_data})
      |> Repo.update!()
      
      # Reset dirty flag
      %{state | dirty: false, last_saved: DateTime.utc_now()}
    else
      state
    end
    
    # Schedule next save
    Process.send_after(self(), :save_to_db, @propagate_interval * 2)
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp via_tuple(room_id) do
    {:via, Registry, {Pendant.CRDTRegistry, "room:#{room_id}"}}
  end
  
  defp lookup(room_id) do
    case Registry.lookup(Pendant.CRDTRegistry, "room:#{room_id}") do
      [{pid, _}] ->
        {:ok, pid}
        
      [] ->
        # Try to start a new manager for this room
        case DynamicSupervisor.start_child(
          Pendant.CRDTSupervisor,
          {__MODULE__, room_id}
        ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = error -> error
        end
    end
  end
  
  defp generate_node_name(room_id) do
    "crdt_node_#{room_id}_#{:rand.uniform(1_000_000)}"
  end
  
  defp apply_operation(crdt, %{type: "add", key: key, value: value}) do
    # Add to set
    DeltaCrdt.mutate(crdt, :add, [key, value])
    {:ok, value}
  end
  
  defp apply_operation(crdt, %{type: "remove", key: key, value: value}) do
    # Remove from set
    DeltaCrdt.mutate(crdt, :remove, [key, value])
    {:ok, value}
  end
  
  defp apply_operation(crdt, %{type: "set", key: key, value: value}) do
    # Set a value in a LWW register
    DeltaCrdt.mutate(crdt, :add, [key, value])
    {:ok, value}
  end
  
  defp apply_operation(crdt, %{type: "increment", key: key}) do
    # Get current counter value
    current_value = get_counter_value(crdt, key)
    new_value = current_value + 1
    
    # Update the counter
    DeltaCrdt.mutate(crdt, :add, [key, new_value])
    {:ok, new_value}
  end
  
  defp apply_operation(crdt, %{type: "decrement", key: key}) do
    # Get current counter value
    current_value = get_counter_value(crdt, key)
    new_value = current_value - 1
    
    # Update the counter
    DeltaCrdt.mutate(crdt, :add, [key, new_value])
    {:ok, new_value}
  end
  
  defp apply_operation(crdt, %{type: "update", key: key, nested_key: nested_key, value: value}) do
    # Get current map
    map_data = get_map_value(crdt, key)
    
    # Update the nested value
    updated_map = Map.put(map_data, nested_key, value)
    
    # Store updated map
    DeltaCrdt.mutate(crdt, :add, [key, updated_map])
    {:ok, updated_map}
  end
  
  defp apply_operation(_crdt, operation) do
    # Unknown operation
    Logger.error("Unknown CRDT operation: #{inspect(operation)}")
    {:error, :unknown_operation}
  end
  
  defp get_counter_value(crdt, key) do
    data = DeltaCrdt.to_map(crdt)
    Map.get(data, key, 0)
  end
  
  defp get_map_value(crdt, key) do
    data = DeltaCrdt.to_map(crdt)
    Map.get(data, key, %{})
  end
  
  defp load_crdt_from_db(crdt, crdt_data) do
    # Add all key-value pairs from the stored data
    Enum.each(crdt_data, fn {key, value} ->
      DeltaCrdt.mutate(crdt, :add, [key, value])
    end)
  end
  
  defp broadcast_change(room_id, operation) do
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "crdt:#{room_id}",
      {:crdt_operation, operation, room_id}
    )
  end
  
  defp broadcast_delta(room_id, delta) do
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "crdt:#{room_id}",
      {:crdt_delta, delta, room_id}
    )
  end
end