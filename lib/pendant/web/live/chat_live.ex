defmodule Pendant.Web.ChatLive do
  @moduledoc """
  LiveView for the chat interface.
  """
  use Phoenix.LiveView
  require Logger
  
  # Helper functions used in templates
  def format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end
  
  def format_size(size) when is_integer(size) do
    cond do
      size < 1024 -> "#{size} B"
      size < 1024 * 1024 -> "#{Float.round(size / 1024, 1)} KB"
      size < 1024 * 1024 * 1024 -> "#{Float.round(size / 1024 / 1024, 1)} MB"
      true -> "#{Float.round(size / 1024 / 1024 / 1024, 1)} GB"
    end
  end
  
  def format_size(_), do: "Unknown size"
  
  alias Pendant.Chat
  alias Phoenix.Socket.Broadcast
  
  @doc """
  Mount the LiveView
  """
  @impl true
  def mount(_params, session, socket) do
    # Generate a user token or use an existing one
    user_id = Map.get(session, "user_id") || get_demo_user_id()
    token = Phoenix.Token.sign(Pendant.Web.Endpoint, "user socket", user_id)
    
    # Get user data
    user = Chat.get_user(user_id) || create_demo_user(user_id)
    
    # Get room list
    public_rooms = Chat.list_public_rooms()
    user_rooms = Chat.list_user_rooms(user_id)
    
    socket = socket
      |> assign(:page_title, "Chat")
      |> assign(:user, user)
      |> assign(:user_id, user_id)
      |> assign(:token, token)
      |> assign(:public_rooms, public_rooms)
      |> assign(:user_rooms, user_rooms)
      |> assign(:current_room, nil)
      |> assign(:messages, [])
      |> assign(:room_users, [])
      |> assign(:new_message, "")
      |> assign(:uploading, false)
      |> assign(:upload_progress, 0)
      |> assign(:online_users, [])
      |> assign(:typing_users, [])
      |> assign(:show_emoji_picker, false)
      |> assign(:file_uploads, [])
      |> assign(:crdt_enabled, false)
      |> assign(:crdt_data, nil)
      |> assign(:collaborative_editing, false)
      
    if connected?(socket) do
      # Subscribe to presence updates
      Phoenix.PubSub.subscribe(Pendant.PubSub, "presence:chat")
    end
    
    {:ok, socket}
  end
  
  @doc """
  Handle parameters
  """
  @impl true
  def handle_params(%{"room_id" => room_id}, _uri, socket) do
    # Join the room
    room_id = String.to_integer(room_id)
    
    # If we already have a room, leave it first
    if socket.assigns.current_room do
      Phoenix.PubSub.unsubscribe(Pendant.PubSub, "chat:room:#{socket.assigns.current_room.id}")
    end
    
    # Get room data
    room = Chat.get_room(room_id)
    messages = Chat.list_room_messages(room_id)
    room_users = Chat.list_room_users(room_id)
    
    # Subscribe to room messages
    Phoenix.PubSub.subscribe(Pendant.PubSub, "chat:room:#{room_id}")
    
    # If room has CRDT, subscribe to CRDT updates
    if room.crdt_enabled do
      Phoenix.PubSub.subscribe(Pendant.PubSub, "crdt:#{room_id}")
    end
    
    socket = socket
      |> assign(:current_room, room)
      |> assign(:messages, messages)
      |> assign(:room_users, room_users)
      |> assign(:crdt_enabled, room.crdt_enabled)
      |> assign(:crdt_data, room.crdt_data)
      |> assign(:new_message, "")
      |> assign(:show_emoji_picker, false)
      |> assign(:collaborative_editing, false)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_params(_params, _uri, socket) do
    # No room specified, just show the room list
    {:noreply, socket}
  end
  
  @doc """
  Handle events from the UI
  """
  @impl true
  def handle_event("send_message", %{"message" => ""}, socket) do
    # Empty message, do nothing
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    # Send a message to the current room
    user_id = socket.assigns.user_id
    room_id = socket.assigns.current_room.id
    
    {:ok, new_message} = Chat.create_message(%{
      content: message,
      message_type: "text",
      user_id: user_id,
      room_id: room_id
    })
    
    # Clear the message input
    socket = socket
      |> assign(:new_message, "")
      |> assign(:typing_users, List.delete(socket.assigns.typing_users, user_id))
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("typing", %{"value" => value}, socket) do
    # Update the message input value
    socket = assign(socket, :new_message, value)
    
    # If room is selected, broadcast that user is typing
    if socket.assigns.current_room do
      user_id = socket.assigns.user_id
      
      # Broadcast typing event if not already in typing users
      unless Enum.member?(socket.assigns.typing_users, user_id) do
        Phoenix.PubSub.broadcast(
          Pendant.PubSub,
          "chat:room:#{socket.assigns.current_room.id}",
          {:user_typing, user_id}
        )
      end
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("upload_file", %{"file" => file}, socket) do
    # Handle file upload
    user_id = socket.assigns.user_id
    room_id = socket.assigns.current_room.id
    
    socket = socket
      |> assign(:uploading, true)
      |> assign(:upload_progress, 0)
    
    # Process the file in a separate task
    Task.start(fn ->
      # Simulate upload progress
      for progress <- [10, 20, 30, 50, 70, 90, 100] do
        :timer.sleep(100)
        send(self(), {:upload_progress, progress})
      end
      
      # Process the file
      case Chat.create_file_message(room_id, user_id, file) do
        {:ok, _message} ->
          send(self(), :upload_complete)
          
        {:error, reason} ->
          send(self(), {:upload_error, reason})
      end
    end)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("toggle_emoji_picker", _, socket) do
    {:noreply, assign(socket, :show_emoji_picker, !socket.assigns.show_emoji_picker)}
  end
  
  @impl true
  def handle_event("select_emoji", %{"emoji" => emoji}, socket) do
    # Add emoji to message
    new_message = socket.assigns.new_message <> emoji
    
    socket = socket
      |> assign(:new_message, new_message)
      |> assign(:show_emoji_picker, false)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("toggle_collaborative_editing", _, socket) do
    if socket.assigns.crdt_enabled do
      # Toggle collaborative editing mode
      {:noreply, assign(socket, :collaborative_editing, !socket.assigns.collaborative_editing)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("crdt_update", %{"operation" => operation}, socket) do
    # Parse operation JSON
    case Jason.decode(operation) do
      {:ok, parsed_operation} ->
        # Update CRDT data
        room_id = socket.assigns.current_room.id
        
        case Chat.update_crdt(room_id, parsed_operation) do
          {:ok, _value} ->
            # Get updated CRDT data
            {:ok, updated_data} = Chat.get_crdt_data(room_id)
            {:noreply, assign(socket, :crdt_data, updated_data)}
            
          {:error, reason} ->
            # Log error
            Logger.error("CRDT update failed: #{inspect(reason)}")
            {:noreply, socket}
        end
        
      {:error, _} ->
        {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("add_set_item", params, socket) do
    # Get item from form
    item = params["set-item"]
    
    if is_binary(item) && String.trim(item) != "" do
      # Create operation
      operation = %{
        type: "add",
        key: "items",
        value: String.trim(item)
      }
      
      # Update CRDT
      room_id = socket.assigns.current_room.id
      
      case Chat.update_crdt(room_id, operation) do
        {:ok, _value} ->
          # Get updated CRDT data
          {:ok, updated_data} = Chat.get_crdt_data(room_id)
          {:noreply, assign(socket, :crdt_data, updated_data)}
          
        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("lww_typing", %{"value" => value}, socket) do
    # Store the value for later use
    {:noreply, assign(socket, :lww_value, value)}
  end
  
  @impl true
  def handle_event("update_lww_value", _params, socket) do
    # Get the value from assign
    value = socket.assigns[:lww_value]
    
    if is_binary(value) && String.trim(value) != "" do
      # Create operation
      operation = %{
        type: "set",
        key: "title",
        value: value
      }
      
      # Update CRDT
      room_id = socket.assigns.current_room.id
      
      case Chat.update_crdt(room_id, operation) do
        {:ok, _value} ->
          # Get updated CRDT data
          {:ok, updated_data} = Chat.get_crdt_data(room_id)
          {:noreply, assign(socket, :crdt_data, updated_data)}
          
        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("join_room", %{"id" => room_id}, socket) do
    # Navigate to the selected room
    {:noreply, push_patch(socket, to: "/chat/#{room_id}")}
  end
  
  @impl true
  def handle_event("create_room", %{"name" => name, "type" => type}, socket) do
    # Create a new room
    user_id = socket.assigns.user_id
    
    case Chat.create_room(%{
      name: name,
      room_type: type,
      description: "Created by #{socket.assigns.user.username}"
    }) do
      {:ok, room} ->
        # Add user to room as owner
        {:ok, _} = Chat.add_user_to_room(user_id, room.id, "owner")
        
        # Refresh room lists
        public_rooms = Chat.list_public_rooms()
        user_rooms = Chat.list_user_rooms(user_id)
        
        socket = socket
          |> assign(:public_rooms, public_rooms)
          |> assign(:user_rooms, user_rooms)
          |> put_flash(:info, "Room created successfully")
          
        # Navigate to the new room
        {:noreply, push_patch(socket, to: "/chat/#{room.id}")}
        
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create room")}
    end
  end
  
  @impl true
  def handle_event("create_crdt_room", %{"name" => name, "crdt_type" => crdt_type}, socket) do
    # Create a new room with CRDT enabled
    user_id = socket.assigns.user_id
    
    case Chat.create_room(%{
      name: name,
      room_type: "public",
      description: "Collaborative room with #{crdt_type} CRDT",
      crdt_enabled: true,
      crdt_type: crdt_type
    }) do
      {:ok, room} ->
        # Add user to room as owner
        {:ok, _} = Chat.add_user_to_room(user_id, room.id, "owner")
        
        # Refresh room lists
        public_rooms = Chat.list_public_rooms()
        user_rooms = Chat.list_user_rooms(user_id)
        
        socket = socket
          |> assign(:public_rooms, public_rooms)
          |> assign(:user_rooms, user_rooms)
          |> put_flash(:info, "Collaborative room created successfully")
          
        # Navigate to the new room
        {:noreply, push_patch(socket, to: "/chat/#{room.id}")}
        
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create collaborative room")}
    end
  end
  
  @doc """
  Handle messages from PubSub
  """
  @impl true
  def handle_info({:new_message, message}, socket) do
    # Add new message to the list
    messages = [message | socket.assigns.messages] |> Enum.sort_by(& &1.inserted_at)
    
    {:noreply, assign(socket, :messages, messages)}
  end
  
  @impl true
  def handle_info({:user_typing, user_id}, socket) do
    # Add user to typing users if not already there
    unless Enum.member?(socket.assigns.typing_users, user_id) do
      typing_users = [user_id | socket.assigns.typing_users]
      
      # Remove typing indicator after 3 seconds
      Process.send_after(self(), {:user_stopped_typing, user_id}, 3000)
      
      {:noreply, assign(socket, :typing_users, typing_users)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info({:user_stopped_typing, user_id}, socket) do
    # Remove user from typing users
    typing_users = List.delete(socket.assigns.typing_users, user_id)
    
    {:noreply, assign(socket, :typing_users, typing_users)}
  end
  
  @impl true
  def handle_info({:upload_progress, progress}, socket) do
    {:noreply, assign(socket, :upload_progress, progress)}
  end
  
  @impl true
  def handle_info(:upload_complete, socket) do
    socket = socket
      |> assign(:uploading, false)
      |> assign(:upload_progress, 0)
      |> put_flash(:info, "File uploaded successfully")
      
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:upload_error, reason}, socket) do
    socket = socket
      |> assign(:uploading, false)
      |> assign(:upload_progress, 0)
      |> put_flash(:error, "Upload failed: #{inspect(reason)}")
      
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:crdt_update, crdt_data, room_id}, socket) do
    # Update CRDT data if we're in the same room
    if socket.assigns.current_room && socket.assigns.current_room.id == room_id do
      {:noreply, assign(socket, :crdt_data, crdt_data)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info({:user_joined_room, user_id, room_id}, socket) do
    # Update room users if we're in the same room
    if socket.assigns.current_room && socket.assigns.current_room.id == room_id do
      room_users = Chat.list_room_users(room_id)
      {:noreply, assign(socket, :room_users, room_users)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info({:user_left_room, user_id, room_id}, socket) do
    # Update room users if we're in the same room
    if socket.assigns.current_room && socket.assigns.current_room.id == room_id do
      room_users = Chat.list_room_users(room_id)
      {:noreply, assign(socket, :room_users, room_users)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info({:user_online, user_id}, socket) do
    # Add user to online users
    online_users = [user_id | socket.assigns.online_users] |> Enum.uniq()
    {:noreply, assign(socket, :online_users, online_users)}
  end
  
  @impl true
  def handle_info({:user_offline, user_id}, socket) do
    # Remove user from online users
    online_users = List.delete(socket.assigns.online_users, user_id)
    {:noreply, assign(socket, :online_users, online_users)}
  end
  
  # Private functions
  
  defp get_demo_user_id do
    # Generate a random user ID for demo purposes
    :rand.uniform(1000)
  end
  
  defp create_demo_user(user_id) do
    # Create a demo user
    {:ok, user} = Chat.create_user(%{
      username: "user_#{user_id}",
      display_name: "User #{user_id}",
      device_id: "device_#{user_id}",
      status: "online"
    })
    
    user
  end
  
  defp user_name(user_id, room_users) do
    # Get user name from room users list
    case Enum.find(room_users, fn u -> u.user.id == user_id end) do
      nil -> "Unknown User"
      user -> user.user.display_name || user.user.username
    end
  end
  
  defp is_user_online?(user_id, online_users) do
    Enum.member?(online_users, user_id)
  end
end