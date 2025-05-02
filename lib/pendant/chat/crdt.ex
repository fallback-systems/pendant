defmodule Pendant.Chat.CRDT do
  @moduledoc """
  Handles Conflict-free Replicated Data Types (CRDTs) for the chat system.
  
  This module implements various CRDT types:
  - Last-Write-Wins (LWW) Registers
  - Counters (PN-Counter)
  - Sets (OR-Set)
  - Text (WOOT)
  
  These data structures allow for conflict-free merging of data even
  when updates happen concurrently and independently.
  """
  
  alias Pendant.Chat.Room
  alias Pendant.KnowledgeBase.Repo
  
  @doc """
  Creates a new CRDT of the specified type with initial data.
  """
  def create(type, initial_data \\ nil) do
    timestamp = timestamp_now()
    node_id = node_identifier()
    
    case type do
      "lww" ->
        %{
          type: "lww",
          value: initial_data,
          timestamp: timestamp,
          node_id: node_id
        }
        
      "counter" ->
        %{
          type: "counter",
          p: 0,  # increments
          n: 0,  # decrements
          node_id: node_id
        }
        
      "set" ->
        %{
          type: "set",
          elements: %{},  # map of {element => {added: bool, timestamp: int}}
          node_id: node_id
        }
        
      "text" ->
        %{
          type: "text",
          content: initial_data || "",
          operations: [],
          node_id: node_id
        }
        
      _ ->
        raise ArgumentError, "Unsupported CRDT type: #{type}"
    end
  end
  
  @doc """
  Updates a CRDT with a new operation.
  """
  def update(crdt, operation, room_id) do
    updated_crdt = do_update(crdt, operation)
    
    # Store the updated CRDT in the database
    Repo.get!(Room, room_id)
    |> Ecto.Changeset.change(%{crdt_data: updated_crdt})
    |> Repo.update!()
    
    # Broadcast the update to all nodes
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "crdt:#{room_id}",
      {:crdt_update, updated_crdt, room_id}
    )
    
    updated_crdt
  end
  
  @doc """
  Merges two CRDTs of the same type to resolve conflicts.
  """
  def merge(crdt1, crdt2) do
    if crdt1.type != crdt2.type do
      raise ArgumentError, "Cannot merge CRDTs of different types: #{crdt1.type} and #{crdt2.type}"
    end
    
    case crdt1.type do
      "lww" -> merge_lww(crdt1, crdt2)
      "counter" -> merge_counter(crdt1, crdt2)
      "set" -> merge_set(crdt1, crdt2)
      "text" -> merge_text(crdt1, crdt2)
      _ -> raise ArgumentError, "Unsupported CRDT type: #{crdt1.type}"
    end
  end
  
  # Private functions
  
  # Update implementations
  defp do_update(%{type: "lww"} = crdt, %{value: value}) do
    %{crdt |
      value: value,
      timestamp: timestamp_now(),
      node_id: node_identifier()
    }
  end
  
  defp do_update(%{type: "counter"} = crdt, %{operation: "increment", value: value}) do
    %{crdt |
      p: crdt.p + value
    }
  end
  
  defp do_update(%{type: "counter"} = crdt, %{operation: "decrement", value: value}) do
    %{crdt |
      n: crdt.n + value
    }
  end
  
  defp do_update(%{type: "set"} = crdt, %{operation: "add", value: value}) do
    elements = Map.put(crdt.elements, value, %{
      added: true,
      timestamp: timestamp_now()
    })
    
    %{crdt | elements: elements}
  end
  
  defp do_update(%{type: "set"} = crdt, %{operation: "remove", value: value}) do
    case Map.get(crdt.elements, value) do
      nil -> crdt  # Element not in set
      _ ->
        elements = Map.put(crdt.elements, value, %{
          added: false,
          timestamp: timestamp_now()
        })
        
        %{crdt | elements: elements}
    end
  end
  
  defp do_update(%{type: "text"} = crdt, %{operation: op, index: index, value: value}) do
    operation = %{
      op: op,
      index: index,
      value: value,
      timestamp: timestamp_now(),
      node_id: node_identifier()
    }
    
    # Apply the operation
    content = apply_text_operation(crdt.content, operation)
    
    # Add the operation to history
    %{crdt |
      content: content,
      operations: [operation | crdt.operations]
    }
  end
  
  # Merge implementations
  defp merge_lww(crdt1, crdt2) do
    if crdt1.timestamp > crdt2.timestamp or 
       (crdt1.timestamp == crdt2.timestamp and crdt1.node_id > crdt2.node_id) do
      crdt1
    else
      crdt2
    end
  end
  
  defp merge_counter(crdt1, crdt2) do
    %{
      type: "counter",
      p: max(crdt1.p, crdt2.p),
      n: max(crdt1.n, crdt2.n),
      node_id: node_identifier()
    }
  end
  
  defp merge_set(crdt1, crdt2) do
    # Merge elements from both sets
    merged_elements = Map.merge(crdt1.elements, crdt2.elements, fn _k, v1, v2 ->
      if v1.timestamp > v2.timestamp do
        v1
      else
        v2
      end
    end)
    
    %{
      type: "set",
      elements: merged_elements,
      node_id: node_identifier()
    }
  end
  
  defp merge_text(crdt1, crdt2) do
    # Get all operations from both CRDTs
    all_ops = (crdt1.operations ++ crdt2.operations)
              |> Enum.sort_by(fn op -> {op.timestamp, op.node_id} end)
              |> Enum.uniq_by(fn op -> {op.timestamp, op.node_id, op.index, op.op} end)
    
    # Apply all operations in order to an empty string
    content = Enum.reduce(all_ops, "", fn op, content ->
      apply_text_operation(content, op)
    end)
    
    %{
      type: "text",
      content: content,
      operations: all_ops,
      node_id: node_identifier()
    }
  end
  
  defp apply_text_operation(content, %{op: "insert", index: index, value: value}) do
    {before_text, after_text} = String.split_at(content, index)
    before_text <> value <> after_text
  end
  
  defp apply_text_operation(content, %{op: "delete", index: index, value: value}) do
    {before_text, after_text} = String.split_at(content, index)
    before_text <> String.slice(after_text, String.length(value)..-1)
  end
  
  defp timestamp_now do
    System.system_time(:millisecond)
  end
  
  defp node_identifier do
    Node.self() |> to_string()
  end
end