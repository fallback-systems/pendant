defmodule Pendant.Web.Socket do
  use Phoenix.Socket
  require Logger
  alias Pendant.Auth

  ## Channels
  channel "chat:*", Pendant.Web.ChatChannel
  channel "crdt:*", Pendant.Web.ChatChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Auth.verify_token(token) do
      {:ok, user_data} ->
        # Add user data to socket
        socket = socket
          |> assign(:user_id, user_data.user_id)
          |> assign(:roles, user_data.roles)
        
        {:ok, socket}
        
      {:error, reason} ->
        # Production would reject connection, but for development we'll allow guest users
        if Mix.env() == :prod do
          Logger.warning("Socket connection rejected: #{inspect(reason)}")
          :error
        else
          # Create a demo user for development
          user_id = :rand.uniform(1000)
          user = Auth.create_demo_user("guest_#{user_id}")
          
          Logger.info("Created demo user for socket connection: #{user.username}")
          
          socket = socket
            |> assign(:user_id, user.id)
            |> assign(:roles, ["guest"])
          
          {:ok, socket}
        end
    end
  end
  
  # Fallback for connections without token
  def connect(_params, socket, _connect_info) do
    if Mix.env() == :prod do
      Logger.warning("Socket connection rejected: no token provided")
      :error
    else
      # Create a demo user for development
      user_id = :rand.uniform(1000)
      user = Auth.create_demo_user("guest_#{user_id}")
      
      Logger.info("Created demo user for socket connection: #{user.username}")
      
      socket = socket
        |> assign(:user_id, user.id)
        |> assign(:roles, ["guest"])
      
      {:ok, socket}
    end
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end