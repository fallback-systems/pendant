defmodule Pendant.Web.RoomController do
  use Phoenix.Controller
  
  alias Pendant.Chat
  alias Pendant.Auth
  
  # This controller is needed for our tests
  
  def show(conn, %{"id" => id}) do
    user_id = conn.assigns.user_id
    
    # Try to parse the ID as an integer
    {room_id, _} = Integer.parse(id)
    
    # Check if user can access the room
    if Auth.can_access_room?(user_id, room_id) do
      room = Chat.get_room(room_id)
      
      conn
      |> put_status(:ok)
      |> render("show.json", %{room: room})
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You don't have permission to access this room"})
    end
  end
  
  def index(conn, _params) do
    user_id = conn.assigns.user_id
    
    # Get rooms the user is a member of
    rooms = Chat.list_user_rooms(user_id)
    
    conn
    |> put_status(:ok)
    |> render("index.json", %{rooms: rooms})
  end
  
  def join(conn, %{"room_id" => id}) do
    user_id = conn.assigns.user_id
    
    # Try to parse the ID as an integer
    {room_id, _} = Integer.parse(id)
    
    case Chat.add_user_to_room(user_id, room_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Joined room successfully"})
        
      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to join room"})
    end
  end
end