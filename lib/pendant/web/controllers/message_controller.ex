defmodule Pendant.Web.MessageController do
  @moduledoc """
  Controller for Meshtastic message API endpoints.
  """
  use Phoenix.Controller
  
  alias Pendant.Meshtastic.Handler, as: MeshtasticHandler
  
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
end