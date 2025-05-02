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
  Lists messages in a room with efficient pagination.
  
  Uses a join instead of preload for better performance and
  adds cursor-based pagination for more efficient queries.
  """
  def list_room_messages(room_id, limit \\ 50, cursor \\ nil) do
    base_query = from m in Message,
                 join: u in User, on: m.user_id == u.id,
                 where: m.room_id == ^room_id,
                 select: %{
                   id: m.id,
                   content: m.content,
                   message_type: m.message_type,
                   file_path: m.file_path,
                   file_name: m.file_name,
                   file_size: m.file_size,
                   file_type: m.file_type,
                   inserted_at: m.inserted_at,
                   user_id: m.user_id,
                   username: u.username,
                   display_name: u.display_name,
                   avatar: u.avatar
                 }
    
    # Apply cursor-based pagination if cursor is provided
    query = if cursor do
      timestamp = cursor
                 |> DateTime.from_iso8601()
                 |> case do
                      {:ok, dt, _} -> dt
                      _ -> DateTime.utc_now()
                    end
                    
      from q in base_query,
           where: q.inserted_at < ^timestamp,
           order_by: [desc: q.inserted_at],
           limit: ^limit
    else
      from q in base_query,
           order_by: [desc: q.inserted_at],
           limit: ^limit
    end
    
    # Get the messages and return in chronological order for UI
    messages = Repo.all(query) |> Enum.reverse()
    
    # If we got exactly the limit, there are probably more messages
    has_more = length(messages) == limit
    
    # Return a cursor for the next page if there are more messages
    new_cursor = if has_more && !Enum.empty?(messages) do
      messages
      |> List.first()
      |> Map.get(:inserted_at)
      |> DateTime.to_iso8601()
    else
      nil
    end
    
    # Convert to proper message structures expected by the UI
    transformed_messages = Enum.map(messages, fn msg ->
      %{
        id: msg.id,
        content: msg.content,
        message_type: msg.message_type,
        file_path: msg.file_path,
        file_name: msg.file_name,
        file_size: msg.file_size,
        file_type: msg.file_type,
        inserted_at: msg.inserted_at,
        user: %{
          id: msg.user_id,
          username: msg.username,
          display_name: msg.display_name,
          avatar: msg.avatar
        },
        user_id: msg.user_id,
        room_id: room_id
      }
    end)
    
    %{
      messages: transformed_messages,
      cursor: new_cursor,
      has_more: has_more
    }
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
  
  Uses streaming for performance and handles errors gracefully.
  """
  def create_file_message(room_id, user_id, file_params) do
    try do
      # Validate file size
      file_size = byte_size(file_params.binary)
      
      # Apply size limit for emergency communication (10MB by default)
      max_file_size = Application.get_env(:pendant, :max_file_size, 10_485_760)
      
      if file_size > max_file_size do
        {:error, "File exceeds maximum allowed size of #{format_file_size(max_file_size)}"}
      else
        # Validate file extension
        original_filename = file_params.filename || "unnamed_file"
        ext = String.downcase(Path.extname(original_filename))
        
        # Security: Only allow safe file extensions
        allowed_extensions = Application.get_env(
          :pendant, 
          :allowed_file_extensions,
          [".jpg", ".jpeg", ".png", ".gif", ".pdf", ".txt", ".md", ".json"]
        )
        
        if Enum.member?(allowed_extensions, ext) || Enum.empty?(allowed_extensions) do
          # Ensure uploads directory exists
          uploads_dir = "/home/user/dev/pendant/priv/static/uploads"
          File.mkdir_p!(uploads_dir)
          
          # Generate unique filename with random component for security
          timestamp = System.system_time(:second)
          random = :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
          sanitized_name = Path.basename(original_filename, ext)
                          |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
                          |> String.slice(0, 30) # Limit filename length
          unique_filename = "#{sanitized_name}_#{timestamp}_#{random}#{ext}"
          
          # Save the file safely with streaming
          file_path = Path.join(uploads_dir, unique_filename)
          
          # Process in chunks to avoid memory issues
          with :ok <- write_file_safely(file_path, file_params.binary) do
            # Create the message
            file_size = File.stat!(file_path).size
            file_type = MIME.from_path(original_filename) || "application/octet-stream"
            
            create_message(%{
              room_id: room_id,
              user_id: user_id,
              content: "Shared a file: #{original_filename}",
              message_type: "file",
              file_path: "/uploads/#{unique_filename}",
              file_name: original_filename,
              file_size: file_size,
              file_type: file_type
            })
          else
            {:error, reason} -> {:error, "Failed to save file: #{reason}"}
          end
        else
          {:error, "File type not allowed. Allowed types: #{Enum.join(allowed_extensions, ", ")}"}
        end
      end
    rescue
      e ->
        Logger.error("File upload failed: #{inspect(e)}")
        {:error, "File upload failed: #{Exception.message(e)}"}
    end
  end
  
  # Write file safely using streaming to handle large files
  defp write_file_safely(file_path, binary_data) do
    # Create temp file first
    temp_path = "#{file_path}.tmp"
    
    try do
      # Open file for writing
      with {:ok, file} <- File.open(temp_path, [:write, :binary]) do
        # Write data in chunks to avoid memory issues
        chunk_size = 1_048_576 # 1MB chunks
        
        # Process data in chunks
        for <<chunk::binary-size(chunk_size) <- binary_data>> do
          IO.binwrite(file, chunk)
        end
        
        # Clean up
        File.close(file)
        
        # Rename from temp to final
        File.rename(temp_path, file_path)
        :ok
      end
    rescue
      e ->
        # Clean up temp file if it exists
        File.rm(temp_path)
        Logger.error("File write failed: #{inspect(e)}")
        {:error, "Write operation failed"}
    catch
      kind, reason ->
        # Clean up temp file if it exists
        File.rm(temp_path)
        Logger.error("File write failed with #{kind}: #{inspect(reason)}")
        {:error, "Write operation failed"}
    end
  end
  
  # Format file size for human readability
  defp format_file_size(size_in_bytes) when is_integer(size_in_bytes) do
    cond do
      size_in_bytes < 1024 ->
        "#{size_in_bytes} B"
      size_in_bytes < 1024 * 1024 ->
        kb = Float.round(size_in_bytes / 1024, 1)
        "#{kb} KB"
      size_in_bytes < 1024 * 1024 * 1024 ->
        mb = Float.round(size_in_bytes / 1024 / 1024, 1)
        "#{mb} MB"
      true ->
        gb = Float.round(size_in_bytes / 1024 / 1024 / 1024, 1)
        "#{gb} GB"
    end
  end
end