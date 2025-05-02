defmodule Pendant.Web.ChatChannel do
  @moduledoc """
  Channel for chat functionality.
  """
  use Phoenix.Channel
  require Logger
  
  alias Pendant.Chat
  import Ecto.Query
  
  #
  # Channel callbacks
  #
  
  @impl true
  def join("chat:room:" <> room_id, _params, socket) do
    try do
      user_id = socket.assigns.user_id
      
      # Try to parse room_id as integer
      {room_id, _} = Integer.parse(room_id)
      
      # Check authorization
      if Pendant.Auth.can_access_room?(user_id, room_id) do
        # Mark user as having read messages up to this point
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        
        # Get messages with pagination
        messages_data = Chat.list_room_messages(room_id, 50)
        room = Chat.get_room(room_id)
        users = Chat.list_room_users(room_id)
        
        # Track that user is in this room
        try do
          Phoenix.PubSub.broadcast(
            Pendant.PubSub,
            "presence:chat",
            {:user_joined_room, user_id, room_id}
          )
        rescue
          e -> Logger.error("Failed to broadcast join event: #{inspect(e)}")
        end
        
        socket = socket
          |> assign(:room_id, room_id)
          |> assign(:joined_at, now)
          |> assign(:rate_limit_key, "user:#{user_id}")
        
        # Send initial data
        {:ok, %{
          messages: Phoenix.View.render_many(messages_data.messages, Pendant.Web.MessageView, "message.json"),
          cursor: messages_data.cursor,
          has_more: messages_data.has_more,
          room: Phoenix.View.render_one(room, Pendant.Web.RoomView, "room.json"),
          users: Phoenix.View.render_many(users, Pendant.Web.UserRoomView, "user_room.json"),
        }, socket}
      else
        {:error, %{reason: "unauthorized"}}
      end
    rescue
      e ->
        Logger.error("Error joining chat room: #{inspect(e)}")
        {:error, %{reason: "server_error"}}
    end
  end
  
  @impl true
  def join("chat:lobby", _payload, socket) do
    # Public lobby for announcements
    {:ok, socket}
  end
  
  @impl true
  def join("chat:direct:" <> target_user_id, _params, socket) do
    # Direct chat between two users
    if String.to_integer(target_user_id) == socket.assigns.user_id do
      {:error, %{reason: "cannot chat with yourself"}}
    else
      # Create or get direct chat room
      case create_or_get_direct_room(socket.assigns.user_id, String.to_integer(target_user_id)) do
        {:ok, room} ->
          # Redirect to the room channel
          {:error, %{reason: "redirect", room_id: room.id}}
          
        {:error, _reason} ->
          {:error, %{reason: "error"}}
      end
    end
  end
  
  @impl true
  def join("chat:presence", _payload, socket) do
    # Global presence tracking
    {:ok, socket}
  end
  
  @impl true
  def join("crdt:" <> room_id, _params, socket) do
    if authorized?(socket, room_id) do
      # Get the CRDT data for this room
      {room_id, _} = Integer.parse(room_id)
      
      case Chat.get_crdt_data(room_id) do
        {:ok, crdt_data} ->
          socket = socket
            |> assign(:room_id, room_id)
          
          # Subscribe to CRDT updates
          Phoenix.PubSub.subscribe(Pendant.PubSub, "crdt:#{room_id}")
          
          {:ok, %{crdt_data: crdt_data}, socket}
          
        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
  
  @impl true
  def handle_in("new_message", %{"content" => content}, socket) do
    # Create a new text message
    user_id = socket.assigns.user_id
    room_id = socket.assigns.room_id
    
    case Chat.create_message(%{
      content: content,
      message_type: "text",
      user_id: user_id,
      room_id: room_id
    }) do
      {:ok, message} ->
        # Message is broadcasted automatically in the create_message function
        {:reply, {:ok, Phoenix.View.render_one(message, Pendant.Web.MessageView, "message.json")}, socket}
        
      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end
  
  @impl true
  def handle_in("upload_file", %{"file" => file_params}, socket) do
    # Create a new file message
    user_id = socket.assigns.user_id
    room_id = socket.assigns.room_id
    
    case Chat.create_file_message(room_id, user_id, file_params) do
      {:ok, message} ->
        {:reply, {:ok, Phoenix.View.render_one(message, Pendant.Web.MessageView, "message.json")}, socket}
        
      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end
  
  @impl true
  def handle_in("update_crdt", %{"operation" => operation}, socket) do
    # Get client key for rate limiting
    client_key = socket.assigns.rate_limit_key
    
    # Check rate limit - CRDT operations cost 3 tokens (higher than messages)
    case Pendant.RateLimiter.check_rate_limit(client_key, "crdt_update", 3) do
      {:ok, remaining} ->
        # Authorized to perform CRDT update
        user_id = socket.assigns.user_id
        room_id = socket.assigns.room_id
        
        # Check if user has permission to modify this CRDT
        if Pendant.Auth.can_modify_crdt?(user_id, room_id) do
          # Try to update CRDT
          try do
            case Chat.update_crdt(room_id, operation) do
              {:ok, value} ->
                # Get the updated CRDT data
                {:ok, crdt_data} = Chat.get_crdt_data(room_id)
                
                # Reply with the updated data
                {:reply, {:ok, %{
                  crdt_data: crdt_data, 
                  updated_value: value,
                  rate_limit: %{
                    remaining: remaining,
                    reset_in: floor(1000 / 2) # Based on refill rate
                  }
                }}, socket}
                
              {:error, reason} ->
                {:reply, {:error, %{reason: reason}}, socket}
            end
          rescue
            e ->
              Logger.error("Error updating CRDT: #{inspect(e)}")
              {:reply, {:error, %{reason: "server_error"}}, socket}
          end
        else
          # Not authorized
          {:reply, {:error, %{reason: "unauthorized"}}, socket}
        end
        
      {:error, :rate_limited} ->
        # Rate limited - get bucket info to tell client when to retry
        bucket = Pendant.RateLimiter.get_bucket(client_key, "crdt_update")
        time_to_token = max(0, ceil((1 - bucket.tokens) / bucket.refill_rate * 1000))
        
        {:reply, {:error, %{
          reason: "rate_limited",
          retry_after: time_to_token
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("sync_crdt_delta", %{"delta" => delta}, socket) do
    # Merge a remote delta with our local CRDT
    room_id = socket.assigns.room_id
    
    case Chat.merge_crdt_delta(room_id, delta) do
      :ok ->
        {:reply, {:ok, %{status: "merged"}}, socket}
        
      {:error, _reason} ->
        {:reply, {:error, %{reason: "error"}}, socket}
    end
  end
  
  @impl true
  def handle_in("get_messages_since", %{"since" => since}, socket) do
    # Get messages since a given timestamp
    room_id = socket.assigns.room_id
    since_datetime = DateTime.from_iso8601(since)
    
    case since_datetime do
      {:ok, datetime, _offset} ->
        messages = Chat.get_messages_since(room_id, datetime)
        
        {:reply, {:ok, %{
          messages: Phoenix.View.render_many(messages, Pendant.Web.MessageView, "message.json")
        }}, socket}
        
      {:error, _reason} ->
        {:reply, {:error, %{reason: "Invalid timestamp format"}}, socket}
    end
  end
  
  @impl true
  def handle_in("typing", _payload, socket) do
    # Broadcast that user is typing
    user_id = socket.assigns.user_id
    _room_id = socket.assigns.room_id
    
    broadcast_from!(socket, "user_typing", %{user_id: user_id})
    
    {:noreply, socket}
  end
  
  @impl true
  # Handle CRDT updates
  def handle_info({:crdt_operation, operation, room_id}, socket) do
    if socket.assigns.room_id == room_id do
      # Broadcast to all clients in this channel
      broadcast!(socket, "crdt_updated", %{operation: operation})
    end
    
    {:noreply, socket}
  end
  
  def handle_info({:crdt_delta, delta, room_id}, socket) do
    if socket.assigns.room_id == room_id do
      # Broadcast delta to all clients in this channel
      broadcast!(socket, "crdt_delta", %{delta: delta})
    end
    
    {:noreply, socket}
  end
  
  def terminate(_reason, socket) do
    # User left the channel
    if Map.has_key?(socket.assigns, :room_id) do
      user_id = socket.assigns.user_id
      room_id = socket.assigns.room_id
      
      Phoenix.PubSub.broadcast(
        Pendant.PubSub,
        "presence:chat",
        {:user_left_room, user_id, room_id}
      )
    end
    
    :ok
  end
  
  #
  # Private functions
  #
  
  defp authorized?(socket, room_id) do
    # Check if user is authorized to join this room
    user_id = socket.assigns.user_id
    {room_id, _} = Integer.parse(room_id)
    room = Chat.get_room(room_id)
    
    cond do
      # Room doesn't exist
      is_nil(room) ->
        false
        
      # Public room - anyone can join
      room.room_type == "public" ->
        # Ensure user is added to the room
        case Chat.add_user_to_room(user_id, room_id) do
          {:ok, _} -> true
          {:error, _} -> true  # Already a member, which is fine
        end
        
      # Private or direct room - check membership
      true ->
        # Use Chat.list_user_rooms and filter to avoid using Ecto query directly
        rooms = Chat.list_user_rooms(user_id)
        Enum.any?(rooms, fn room -> room.id == room_id end)
    end
  end
  
  defp create_or_get_direct_room(user1_id, user2_id) do
    # Implementation for creating or getting a direct room
    # A simplified version for testing
    
    # Sort user IDs to ensure consistent room naming
    [u1, u2] = Enum.sort([user1_id, user2_id])
    
    # Try to find existing direct room
    user1 = Chat.get_user(u1)
    user2 = Chat.get_user(u2)
    
    room_name = "Direct: #{user1.username} & #{user2.username}"
    existing_room = Chat.get_room_by_name(room_name)
    
    if existing_room do
      {:ok, existing_room}
    else
      # Create a new direct room
      case Chat.create_room(%{
        name: room_name,
        room_type: "direct",
        description: "Direct conversation"
      }) do
        {:ok, room} ->
          # Add both users to the room
          Chat.add_user_to_room(u1, room.id, "member")
          Chat.add_user_to_room(u2, room.id, "member")
          
          {:ok, room}
          
        error ->
          error
      end
    end
  end
  
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end