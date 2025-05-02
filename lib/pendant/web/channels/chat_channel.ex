defmodule Pendant.Web.ChatChannel do
  @moduledoc """
  Channel for chat functionality.
  """
  use Phoenix.Channel
  require Logger
  
  alias Pendant.Chat
  
  #
  # Channel callbacks
  #
  
  @impl true
  def join("chat:room:" <> room_id, params, socket) do
    if authorized?(socket, room_id) do
      user_id = socket.assigns.user_id
      
      # Try to parse room_id as integer
      {room_id, _} = Integer.parse(room_id)
      
      # Mark user as having read messages up to this point
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      
      # Get messages
      messages = Chat.list_room_messages(room_id)
      room = Chat.get_room(room_id)
      users = Chat.list_room_users(room_id)
      
      # Track that user is in this room
      Phoenix.PubSub.broadcast(
        Pendant.PubSub,
        "presence:chat",
        {:user_joined_room, user_id, room_id}
      )
      
      socket = socket
        |> assign(:room_id, room_id)
        |> assign(:joined_at, now)
      
      # Send initial data
      {:ok, %{
        messages: Phoenix.View.render_many(messages, Pendant.Web.MessageView, "message.json"),
        room: Phoenix.View.render_one(room, Pendant.Web.RoomView, "room.json"),
        users: Phoenix.View.render_many(users, Pendant.Web.UserRoomView, "user_room.json"),
      }, socket}
    else
      {:error, %{reason: "unauthorized"}}
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
          
        {:error, reason} ->
          {:error, %{reason: reason}}
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
    # Update the CRDT for this room
    room_id = socket.assigns.room_id
    
    case Chat.update_crdt(room_id, operation) do
      {:ok, value} ->
        # Get the updated CRDT data
        {:ok, crdt_data} = Chat.get_crdt_data(room_id)
        
        # Reply with the updated data
        {:reply, {:ok, %{
          crdt_data: crdt_data, 
          updated_value: value
        }}, socket}
        
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end
  
  @impl true
  def handle_in("sync_crdt_delta", %{"delta" => delta}, socket) do
    # Merge a remote delta with our local CRDT
    room_id = socket.assigns.room_id
    
    case Chat.merge_crdt_delta(room_id, delta) do
      :ok ->
        {:reply, {:ok, %{status: "merged"}}, socket}
        
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
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
        
      {:error, reason} ->
        {:reply, {:error, %{reason: "Invalid timestamp format"}}, socket}
    end
  end
  
  @impl true
  def handle_in("typing", _payload, socket) do
    # Broadcast that user is typing
    user_id = socket.assigns.user_id
    room_id = socket.assigns.room_id
    
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
        query = from ur in Pendant.Chat.UserRoom,
                where: ur.user_id == ^user_id and ur.room_id == ^room_id,
                select: ur.id
        
        case Pendant.KnowledgeBase.Repo.one(query) do
          nil -> false
          _ -> true
        end
    end
  end
  
  defp create_or_get_direct_room(user1_id, user2_id) do
    # Look for existing direct room between these users
    [u1, u2] = Enum.sort([user1_id, user2_id])
    
    query = from r in Pendant.Chat.Room,
            join: ur1 in Pendant.Chat.UserRoom, on: r.id == ur1.room_id,
            join: ur2 in Pendant.Chat.UserRoom, on: r.id == ur2.room_id,
            where: r.room_type == "direct" and
                  ur1.user_id == ^u1 and
                  ur2.user_id == ^u2,
            select: r
    
    case Pendant.KnowledgeBase.Repo.one(query) do
      nil ->
        # Create a new direct room
        user1 = Chat.get_user(u1)
        user2 = Chat.get_user(u2)
        
        room_name = "Direct: #{user1.username} & #{user2.username}"
        
        Pendant.KnowledgeBase.Repo.transaction(fn ->
          # Create room
          {:ok, room} = Chat.create_room(%{
            name: room_name,
            room_type: "direct",
            description: "Direct conversation"
          })
          
          # Add both users
          {:ok, _} = Chat.add_user_to_room(u1, room.id, "member")
          {:ok, _} = Chat.add_user_to_room(u2, room.id, "member")
          
          room
        end)
        
      room ->
        {:ok, room}
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