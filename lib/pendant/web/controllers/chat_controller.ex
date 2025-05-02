defmodule Pendant.Web.ChatController do
  @moduledoc """
  Controller for the Chat API endpoints.
  """
  use Phoenix.Controller
  
  alias Pendant.Chat
  alias Pendant.Chat.CRDT
  
  @doc """
  Create a new user.
  """
  def create_user(conn, %{"username" => username, "device_id" => device_id} = params) do
    display_name = Map.get(params, "display_name", username)
    
    case Chat.create_user(%{
      username: username,
      display_name: display_name,
      device_id: device_id,
      status: "online"
    }) do
      {:ok, user} ->
        # Generate auth token
        token = Phoenix.Token.sign(Pendant.Web.Endpoint, "user socket", user.id)
        
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          user: %{
            id: user.id,
            username: user.username,
            display_name: user.display_name,
            token: token
          }
        })
        
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          errors: format_errors(changeset)
        })
    end
  end
  
  @doc """
  List all public rooms.
  """
  def list_rooms(conn, _params) do
    rooms = Chat.list_public_rooms()
    
    conn |> json(%{
      status: "success",
      rooms: Enum.map(rooms, fn room ->
        %{
          id: room.id,
          name: room.name,
          description: room.description,
          room_type: room.room_type,
          crdt_enabled: room.crdt_enabled,
          crdt_type: room.crdt_type
        }
      end)
    })
  end
  
  @doc """
  Get details for a specific room.
  """
  def get_room(conn, %{"id" => id}) do
    case Chat.get_room(String.to_integer(id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Room not found"})
        
      room ->
        conn |> json(%{
          status: "success",
          room: %{
            id: room.id,
            name: room.name,
            description: room.description,
            room_type: room.room_type,
            crdt_enabled: room.crdt_enabled,
            crdt_type: room.crdt_type
          }
        })
    end
  end
  
  @doc """
  Create a new room.
  """
  def create_room(conn, %{"name" => name, "user_id" => user_id} = params) do
    room_type = Map.get(params, "room_type", "public")
    description = Map.get(params, "description", "")
    crdt_enabled = Map.get(params, "crdt_enabled", false)
    crdt_type = Map.get(params, "crdt_type")
    
    # Create room
    room_attrs = %{
      name: name,
      description: description,
      room_type: room_type,
      crdt_enabled: crdt_enabled,
      crdt_type: crdt_type
    }
    
    case Chat.create_room(room_attrs) do
      {:ok, room} ->
        # Add user to room as owner
        {:ok, _} = Chat.add_user_to_room(String.to_integer(user_id), room.id, "owner")
        
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          room: %{
            id: room.id,
            name: room.name,
            description: room.description,
            room_type: room.room_type,
            crdt_enabled: room.crdt_enabled,
            crdt_type: room.crdt_type
          }
        })
        
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          errors: format_errors(changeset)
        })
    end
  end
  
  @doc """
  Join a room.
  """
  def join_room(conn, %{"room_id" => room_id, "user_id" => user_id}) do
    room_id = String.to_integer(room_id)
    user_id = String.to_integer(user_id)
    
    case Chat.get_room(room_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", message: "Room not found"})
        
      room ->
        if room.room_type == "public" do
          # Add user to room
          case Chat.add_user_to_room(user_id, room_id) do
            {:ok, _} ->
              conn |> json(%{status: "success", message: "Joined room successfully"})
              
            {:error, _changeset} ->
              conn |> json(%{status: "success", message: "Already a member of this room"})
          end
        else
          # Check if user is already a member
          user_rooms = Chat.list_user_rooms(user_id)
          
          if Enum.any?(user_rooms, fn ur -> ur.id == room_id end) do
            conn |> json(%{status: "success", message: "Already a member of this room"})
          else
            conn
            |> put_status(:forbidden)
            |> json(%{status: "error", message: "Cannot join private room"})
          end
        end
    end
  end
  
  @doc """
  Send a message to a room.
  """
  def send_message(conn, %{"room_id" => room_id, "user_id" => user_id, "content" => content}) do
    room_id = String.to_integer(room_id)
    user_id = String.to_integer(user_id)
    
    # Check if user is a member of the room
    user_rooms = Chat.list_user_rooms(user_id)
    
    if Enum.any?(user_rooms, fn ur -> ur.id == room_id end) do
      case Chat.create_message(%{
        content: content,
        message_type: "text",
        user_id: user_id,
        room_id: room_id
      }) do
        {:ok, message} ->
          conn |> json(%{
            status: "success",
            message: %{
              id: message.id,
              content: message.content,
              message_type: message.message_type,
              inserted_at: message.inserted_at
            }
          })
          
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            status: "error",
            errors: format_errors(changeset)
          })
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{status: "error", message: "Not a member of this room"})
    end
  end
  
  @doc """
  Get messages from a room.
  """
  def get_messages(conn, %{"room_id" => room_id, "user_id" => user_id} = params) do
    room_id = String.to_integer(room_id)
    user_id = String.to_integer(user_id)
    limit = Map.get(params, "limit", "50") |> String.to_integer()
    
    # Check if user is a member of the room
    user_rooms = Chat.list_user_rooms(user_id)
    
    if Enum.any?(user_rooms, fn ur -> ur.id == room_id end) do
      messages = Chat.list_room_messages(room_id, limit)
      
      conn |> json(%{
        status: "success",
        messages: Enum.map(messages, fn message ->
          %{
            id: message.id,
            content: message.content,
            message_type: message.message_type,
            user_id: message.user_id,
            user_username: message.user.username,
            user_display_name: message.user.display_name,
            inserted_at: message.inserted_at,
            file_path: message.file_path,
            file_name: message.file_name,
            file_type: message.file_type,
            file_size: message.file_size
          }
        end)
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%{status: "error", message: "Not a member of this room"})
    end
  end
  
  @doc """
  Get CRDT data for a room.
  """
  def get_crdt(conn, %{"room_id" => room_id, "user_id" => user_id}) do
    room_id = String.to_integer(room_id)
    user_id = String.to_integer(user_id)
    
    # Check if user is a member of the room
    user_rooms = Chat.list_user_rooms(user_id)
    
    if Enum.any?(user_rooms, fn ur -> ur.id == room_id end) do
      case Chat.get_crdt_data(room_id) do
        {:ok, crdt_data} ->
          conn |> json(%{
            status: "success",
            crdt_data: crdt_data
          })
          
        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            status: "error",
            message: reason
          })
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{status: "error", message: "Not a member of this room"})
    end
  end
  
  @doc """
  Update CRDT data for a room.
  """
  def update_crdt(conn, %{"room_id" => room_id, "user_id" => user_id, "operation" => operation}) do
    room_id = String.to_integer(room_id)
    user_id = String.to_integer(user_id)
    
    # Check if user is a member of the room
    user_rooms = Chat.list_user_rooms(user_id)
    
    if Enum.any?(user_rooms, fn ur -> ur.id == room_id end) do
      case Chat.update_crdt(room_id, operation) do
        updated_crdt when is_map(updated_crdt) ->
          conn |> json(%{
            status: "success",
            crdt_data: updated_crdt
          })
          
        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            status: "error",
            message: reason
          })
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{status: "error", message: "Not a member of this room"})
    end
  end
  
  @doc """
  Get users in a room.
  """
  def get_room_users(conn, %{"room_id" => room_id, "user_id" => user_id}) do
    room_id = String.to_integer(room_id)
    user_id = String.to_integer(user_id)
    
    # Check if user is a member of the room
    user_rooms = Chat.list_user_rooms(user_id)
    
    if Enum.any?(user_rooms, fn ur -> ur.id == room_id end) do
      room_users = Chat.list_room_users(room_id)
      
      conn |> json(%{
        status: "success",
        users: Enum.map(room_users, fn user_data ->
          %{
            id: user_data.user.id,
            username: user_data.user.username,
            display_name: user_data.user.display_name,
            avatar: user_data.user.avatar,
            status: user_data.user.status,
            role: user_data.role
          }
        end)
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%{status: "error", message: "Not a member of this room"})
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