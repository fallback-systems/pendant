defmodule Pendant.Web.MessageController do
  @moduledoc """
  Controller for Meshtastic message API endpoints and chat messages.
  """
  use Phoenix.Controller
  
  alias Pendant.Chat
  alias Pendant.Auth
  alias Pendant.Meshtastic.Handler, as: MeshtasticHandler
  
  # Chat-related functions (used in tests)
  
  def index(conn, %{"room_id" => room_id_str}) do
    user_id = conn.assigns.user_id
    {room_id, _} = Integer.parse(room_id_str)
    
    # Check if user can access the room
    if Auth.can_access_room?(user_id, room_id) do
      # Get messages with pagination
      result = Chat.list_room_messages(room_id, 50)
      
      conn
      |> put_status(:ok)
      |> json(%{
        data: Enum.map(result.messages, fn message ->
          %{
            id: message.id,
            content: message.content,
            message_type: message.message_type,
            file_path: message.file_path,
            file_name: message.file_name,
            file_size: message.file_size,
            file_type: message.file_type,
            inserted_at: message.inserted_at,
            user_id: message.user_id
          }
        end),
        cursor: result.cursor,
        has_more: result.has_more
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You don't have permission to access this room"})
    end
  end
  
  def create(conn, %{"room_id" => room_id_str, "content" => content}) do
    user_id = conn.assigns.user_id
    {room_id, _} = Integer.parse(room_id_str)
    
    # Check if user can access the room
    if Auth.can_access_room?(user_id, room_id) do
      case Chat.create_message(%{
        content: content,
        message_type: "text",
        user_id: user_id,
        room_id: room_id
      }) do
        {:ok, message} ->
          conn
          |> put_status(:created)
          |> json(%{
            data: %{
              id: message.id,
              content: message.content,
              message_type: message.message_type,
              inserted_at: message.inserted_at,
              user_id: message.user_id
            }
          })
          
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You don't have permission to access this room"})
    end
  end
  
  # Original Meshtastic functions
  
  def send(conn, %{"message" => message, "to" => recipient}) do
    # Send message to specific recipient
    MeshtasticHandler.send_message(message, recipient)
    
    json(conn, %{
      status: "success",
      message: "Message sent to #{recipient}"
    })
  end
  
  def send(conn, %{"message" => message}) do
    # Broadcast message to all peers
    MeshtasticHandler.send_message(message)
    
    json(conn, %{
      status: "success",
      message: "Message broadcasted to all peers"
    })
  end
  
  def send(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      status: "error",
      message: "Missing required parameter: message"
    })
  end
  
  def history(conn, _params) do
    # Get message history
    messages = MeshtasticHandler.get_message_history()
    
    json(conn, %{
      status: "success",
      count: length(messages),
      messages: messages
    })
  end
  
  def status(conn, _params) do
    # Get Meshtastic status
    status = MeshtasticHandler.status()
    
    json(conn, %{
      status: "success",
      connected: status.connected,
      device: status.device,
      peers: status.peers,
      pending_messages: status.pending_messages
    })
  end
  
  # Helper functions
  
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end