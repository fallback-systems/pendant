defmodule Pendant.Chat do
  @moduledoc """
  The Chat context provides functions for working with the chat system.
  """
  
  import Ecto.Query, warn: false
  alias Pendant.KnowledgeBase.Repo
  alias Pendant.Chat.{User, Room, Message, UserRoom, CRDTManager}

  #
  # User functions
  #
  
  @doc """
  Gets a user by ID.
  """
  def get_user(id), do: Repo.get(User, id)
  
  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end
  
  @doc """
  Gets a user by device ID.
  """
  def get_user_by_device_id(device_id) do
    Repo.get_by(User, device_id: device_id)
  end
  
  @doc """
  Creates a new user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
  
  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end
  
  @doc """
  Updates a user's status.
  """
  def update_user_status(%User{} = user, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    
    user
    |> User.changeset(%{status: status, last_seen_at: now})
    |> Repo.update()
  end
  
  @doc """
  Lists all online users.
  """
  def list_online_users do
    User
    |> where([u], u.status == "online")
    |> order_by([u], u.username)
    |> Repo.all()
  end
  
  #
  # Room functions
  #
  
  @doc """
  Gets a room by ID.
  """
  def get_room(id), do: Repo.get(Room, id)
  
  @doc """
  Gets a room by name.
  """
  def get_room_by_name(name) do
    Repo.get_by(Room, name: name)
  end
  
  @doc """
  Creates a new room.
  """
  def create_room(attrs \\ %{}) do
    # If CRDT is enabled, initialize the CRDT data
    attrs = if attrs[:crdt_enabled] || attrs["crdt_enabled"] do
      crdt_type = attrs[:crdt_type] || attrs["crdt_type"]
      crdt_data = CRDT.create(crdt_type)
      
      Map.put(attrs, :crdt_data, crdt_data)
    else
      attrs
    end
    
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end
  
  @doc """
  Updates a room.
  """
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end
  
  @doc """
  Lists all public rooms.
  """
  def list_public_rooms do
    Room
    |> where([r], r.room_type == "public")
    |> order_by([r], r.name)
    |> Repo.all()
  end
  
  @doc """
  Lists all rooms a user is a member of.
  """
  def list_user_rooms(user_id) do
    query = from r in Room,
            join: ur in UserRoom, on: r.id == ur.room_id,
            where: ur.user_id == ^user_id,
            order_by: [r.name],
            preload: [:user_rooms]
            
    Repo.all(query)
  end
  
  @doc """
  Adds a user to a room.
  """
  def add_user_to_room(user_id, room_id, role \\ "member") do
    %UserRoom{}
    |> UserRoom.changeset(%{
      user_id: user_id,
      room_id: room_id,
      role: role,
      last_read_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end
  
  @doc """
  Removes a user from a room.
  """
  def remove_user_from_room(user_id, room_id) do
    from(ur in UserRoom, where: ur.user_id == ^user_id and ur.room_id == ^room_id)
    |> Repo.delete_all()
  end
  
  @doc """
  Lists users in a room.
  """
  def list_room_users(room_id) do
    query = from u in User,
            join: ur in UserRoom, on: u.id == ur.user_id,
            where: ur.room_id == ^room_id,
            order_by: [u.username],
            select: %{user: u, role: ur.role, last_read_at: ur.last_read_at}
            
    Repo.all(query)
  end
  
  #
  # Message functions
  #
  
  @doc """
  Gets a message by ID.
  """
  def get_message(id), do: Repo.get(Message, id) |> Repo.preload([:user])
  
  @doc """
  Creates a new message.
  """
  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = Repo.preload(message, [:user])
        
        # Broadcast the new message
        Phoenix.PubSub.broadcast(
          Pendant.PubSub,
          "chat:room:#{message.room_id}",
          {:new_message, message}
        )
        
        {:ok, message}
        
      error ->
        error
    end
  end
  
  @doc """
  Lists messages in a room.
  """
  def list_room_messages(room_id, limit \\ 50) do
    Message
    |> where([m], m.room_id == ^room_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> preload([:user])
    |> Repo.all()
    |> Enum.reverse()
  end
  
  @doc """
  Gets messages in a room since a given timestamp.
  """
  def get_messages_since(room_id, since) do
    Message
    |> where([m], m.room_id == ^room_id and m.inserted_at > ^since)
    |> order_by([m], asc: m.inserted_at)
    |> preload([:user])
    |> Repo.all()
  end
  
  #
  # CRDT functions
  #
  
  @doc """
  Updates a CRDT for a room.
  """
  def update_crdt(room_id, operation) do
    room = get_room(room_id)
    
    if room && room.crdt_enabled do
      CRDTManager.update_crdt(room_id, operation)
    else
      {:error, "CRDT not enabled for this room"}
    end
  end
  
  @doc """
  Merges a CRDT delta with the room's CRDT.
  """
  def merge_crdt_delta(room_id, delta) do
    room = get_room(room_id)
    
    if room && room.crdt_enabled do
      CRDTManager.merge_delta(room_id, delta)
    else
      {:error, "CRDT not enabled for this room"}
    end
  end
  
  @doc """
  Gets the current CRDT data for a room.
  """
  def get_crdt_data(room_id) do
    room = get_room(room_id)
    
    if room && room.crdt_enabled do
      CRDTManager.get_crdt_data(room_id)
    else
      {:error, "CRDT not enabled for this room"}
    end
  end
  
  #
  # File transfer functions
  #
  
  @doc """
  Saves an uploaded file and creates a file message.
  """
  def create_file_message(room_id, user_id, file_params) do
    # Ensure uploads directory exists
    File.mkdir_p!("/home/user/dev/pendant/priv/static/uploads")
    
    # Generate unique filename
    timestamp = System.system_time(:second)
    original_filename = file_params.filename
    ext = Path.extname(original_filename)
    sanitized_name = Path.basename(original_filename, ext)
                    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    unique_filename = "#{sanitized_name}_#{timestamp}#{ext}"
    
    # Save the file
    file_path = "/home/user/dev/pendant/priv/static/uploads/#{unique_filename}"
    File.write!(file_path, file_params.binary)
    
    # Create the message
    create_message(%{
      room_id: room_id,
      user_id: user_id,
      content: "Shared a file: #{original_filename}",
      message_type: "file",
      file_path: "/uploads/#{unique_filename}",
      file_name: original_filename,
      file_size: byte_size(file_params.binary),
      file_type: MIME.from_path(original_filename) || "application/octet-stream"
    })
  end
end