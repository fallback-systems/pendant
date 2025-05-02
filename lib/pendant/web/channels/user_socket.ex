defmodule Pendant.Web.UserSocket do
  use Phoenix.Socket
  
  ## Channels
  channel "chat:*", Pendant.Web.ChatChannel
  channel "crdt:*", Pendant.Web.ChatChannel
  
  ## Socket params authentication
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # Verify token and extract user_id
    # In a production app, you'd use a proper token verification
    # For this example, we'll use a simple approach
    case Phoenix.Token.verify(Pendant.Web.Endpoint, "user socket", token, max_age: 86400) do
      {:ok, user_id} ->
        # Get or create the user
        user = 
          case Pendant.Chat.get_user(user_id) do
            nil ->
              # For demo purposes, create a user if not found
              # In a real app, you'd probably reject the connection
              {:ok, user} = Pendant.Chat.create_user(%{
                username: "user_#{user_id}",
                display_name: "User #{user_id}",
                device_id: "device_#{user_id}"
              })
              user
              
            user ->
              user
          end
          
        # Update user status to online
        Pendant.Chat.update_user_status(user, "online")
        
        # Broadcast that user is online
        Phoenix.PubSub.broadcast(
          Pendant.PubSub, 
          "presence:chat",
          {:user_online, user_id}
        )
        
        {:ok, assign(socket, :user_id, user_id)}
        
      {:error, _reason} ->
        :error
    end
  end
  
  # Accept connections without token for demo purposes
  # In production, you'd reject these
  def connect(params, socket, _connect_info) do
    # Generate a random user_id for demo
    user_id = :rand.uniform(1000)
    
    # Create a new user
    {:ok, user} = Pendant.Chat.create_user(%{
      username: "guest_#{user_id}",
      display_name: "Guest #{user_id}",
      device_id: "device_#{user_id}"
    })
    
    # Update user status to online
    Pendant.Chat.update_user_status(user, "online")
    
    # Broadcast that user is online
    Phoenix.PubSub.broadcast(
      Pendant.PubSub, 
      "presence:chat",
      {:user_online, user.id}
    )
    
    {:ok, assign(socket, :user_id, user.id)}
  end
  
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  
  @impl true
  def disconnect(socket) do
    # Update user status to offline
    user_id = socket.assigns.user_id
    
    if user = Pendant.Chat.get_user(user_id) do
      Pendant.Chat.update_user_status(user, "offline")
      
      # Broadcast that user is offline
      Phoenix.PubSub.broadcast(
        Pendant.PubSub, 
        "presence:chat",
        {:user_offline, user_id}
      )
    end
  end
end