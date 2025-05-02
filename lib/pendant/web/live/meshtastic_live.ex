defmodule Pendant.Web.MeshtasticLive do
  @moduledoc """
  LiveView for Meshtastic messaging interface.
  """
  use Phoenix.LiveView
  require Logger
  
  # Helper function used in the template
  def format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end
  
  alias Pendant.Meshtastic.Handler, as: MeshtasticHandler
  
  @message_limit 50  # Number of messages to keep in history
  @update_interval 5000  # Update status every 5 seconds
  
  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to meshtastic message events
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Pendant.PubSub, "meshtastic:messages")
      :timer.send_interval(@update_interval, self(), :update_status)
    end
    
    # Get the current message history
    message_history = MeshtasticHandler.get_message_history()
    
    socket = socket
      |> assign(:page_title, "Meshtastic Messaging")
      |> assign(:status, MeshtasticHandler.status())
      |> assign(:messages, message_history)
      |> assign(:new_message, "")
      |> assign(:selected_peer, nil)
      |> assign(:loading, false)
      |> assign(:error, nil)
    
    {:ok, socket}
  end
  
  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket |> put_flash(:error, "Message cannot be empty")}
    else
      # Send the message
      socket = send_meshtastic_message(socket, message)
      
      # Clear the message input and any previous errors
      socket = socket
        |> assign(:new_message, "")
        |> assign(:error, nil)
        
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("select_peer", %{"peer" => peer}, socket) do
    {:noreply, assign(socket, :selected_peer, peer)}
  end
  
  @impl true
  def handle_event("broadcast_message", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket |> put_flash(:error, "Message cannot be empty")}
    else
      # Broadcast message to all peers
      MeshtasticHandler.send_message(message)
      
      # Add sent message to our message list
      messages = add_message_to_history(socket.assigns.messages, %{
        from: "You (broadcast)",
        payload: message,
        timestamp: DateTime.utc_now(),
        type: :outgoing
      })
      
      # Clear the message input and update messages
      socket = socket
        |> assign(:new_message, "")
        |> assign(:messages, messages)
        |> assign(:error, nil)
        
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("typing", %{"message" => message}, socket) do
    {:noreply, assign(socket, :new_message, message)}
  end
  
  @impl true
  def handle_info({:message, message}, socket) do
    # Add received message to history
    new_message = Map.put(message, :type, :incoming)
    messages = add_message_to_history(socket.assigns.messages, new_message)
    
    {:noreply, assign(socket, :messages, messages)}
  end
  
  @impl true
  def handle_info(:update_status, socket) do
    {:noreply, assign(socket, :status, MeshtasticHandler.status())}
  end
  
  # Private functions
  
  defp send_meshtastic_message(socket, message) do
    # Check if sending to a specific peer or broadcasting
    case socket.assigns.selected_peer do
      nil ->
        # Broadcast to all peers
        MeshtasticHandler.send_message(message)
        
        # Add message to history
        messages = add_message_to_history(socket.assigns.messages, %{
          from: "You (broadcast)",
          payload: message,
          timestamp: DateTime.utc_now(),
          type: :outgoing
        })
        
        assign(socket, :messages, messages)
        
      peer_id ->
        # Send to specific peer
        MeshtasticHandler.send_message(message, peer_id)
        
        # Add message to history
        messages = add_message_to_history(socket.assigns.messages, %{
          from: "You → #{peer_id}",
          payload: message,
          timestamp: DateTime.utc_now(),
          type: :outgoing
        })
        
        assign(socket, :messages, messages)
    end
  end
  
  defp add_message_to_history(messages, new_message) do
    # Add message to list and limit size
    [new_message | messages]
    |> Enum.take(@message_limit)
  end
end