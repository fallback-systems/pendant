defmodule Pendant.Meshtastic.MessageHandler do
  @moduledoc """
  Processes and responds to Meshtastic messages.
  
  This module handles incoming messages from the Meshtastic network and
  determines appropriate responses or actions.
  """
  
  use GenServer
  require Logger
  alias Pendant.Meshtastic.Handler, as: MeshtasticHandler
  alias Pendant.KnowledgeBase.Search
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  # GenServer Implementation
  
  def init(_opts) do
    # Subscribe to Meshtastic messages
    :ok = Phoenix.PubSub.subscribe(Pendant.PubSub, "meshtastic:messages")
    
    {:ok, %{}}
  end
  
  def handle_info({:message, message}, state) do
    # Process the incoming message
    Task.start(fn -> process_message(message) end)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp process_message(message) do
    # Extract command from message if present
    case extract_command(message.payload) do
      {:command, cmd, args} ->
        # Handle command
        handle_command(cmd, args, message.from)
        
      :no_command ->
        # Just log the message
        Logger.info("Received message: #{message.payload} from #{message.from}")
    end
  end
  
  defp extract_command(payload) do
    # Check if the message starts with a command prefix
    if String.starts_with?(payload, "!") do
      # Split into command and arguments
      [cmd | args] = payload 
        |> String.trim_leading("!") 
        |> String.split(" ", parts: 2)
        
      {:command, String.downcase(cmd), args}
    else
      :no_command
    end
  end
  
  defp handle_command("ping", _args, from) do
    # Respond to ping request
    MeshtasticHandler.send_message("pong", from)
  end
  
  defp handle_command("status", _args, from) do
    # Get and send system status
    status = get_system_status()
    MeshtasticHandler.send_message("Status: #{status}", from)
  end
  
  defp handle_command("help", _args, from) do
    # Send help information
    help_text = """
    Available commands:
    !ping - Check connection
    !status - Get system status
    !help - Show this help
    !info - Show device information
    !search [query] - Search knowledge base
    !network - Show network status
    """
    
    MeshtasticHandler.send_message(help_text, from)
  end
  
  defp handle_command("info", _args, from) do
    # Send device information
    info = %{
      device_type: "Pendant Emergency Communication Device",
      version: Application.spec(:pendant, :vsn),
      uptime: get_uptime(),
      knowledge_base_entries: Search.count_entries()
    }
    
    info_text = """
    Device: #{info.device_type}
    Version: #{info.version}
    Uptime: #{info.uptime}
    Knowledge Base: #{info.knowledge_base_entries} entries
    """
    
    MeshtasticHandler.send_message(info_text, from)
  end
  
  defp handle_command("search", args, from) do
    # Search the knowledge base
    query = Enum.join(args, " ")
    
    case Search.find(query) do
      {:ok, results} when results != [] ->
        # Format the results as a message
        message = format_search_results(results)
        MeshtasticHandler.send_message(message, from)
        
      {:ok, []} ->
        MeshtasticHandler.send_message("No results found for: #{query}", from)
        
      {:error, reason} ->
        MeshtasticHandler.send_message("Search error: #{reason}", from)
    end
  end
  
  defp handle_command("network", _args, from) do
    # Get network status
    network_status = %{
      peers: length(MeshtasticHandler.status().peers),
      wifi_ap: Pendant.WiFi.AccessPoint.status(),
      wifi_client: Pendant.WiFi.Client.status()
    }
    
    status_text = """
    Meshtastic Peers: #{network_status.peers}
    WiFi AP: #{if network_status.wifi_ap.active, do: "Active", else: "Inactive"}
    WiFi Client: #{if network_status.wifi_client.connected, do: "Connected to #{network_status.wifi_client.ssid}", else: "Disconnected"}
    """
    
    MeshtasticHandler.send_message(status_text, from)
  end
  
  defp handle_command(unknown_cmd, _args, from) do
    # Handle unknown command
    MeshtasticHandler.send_message("Unknown command: #{unknown_cmd}. Type !help for available commands.", from)
  end
  
  defp get_system_status do
    # Get basic system status information
    %{
      memory: :erlang.memory(),
      disk: get_disk_usage(),
      node: Node.self(),
      uptime: get_uptime()
    }
    |> inspect(pretty: true)
  end
  
  defp get_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime, 1000)
    
    days = div(seconds, 86400)
    seconds = rem(seconds, 86400)
    hours = div(seconds, 3600)
    seconds = rem(seconds, 3600)
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)
    
    "#{days}d #{hours}h #{minutes}m #{seconds}s"
  end
  
  defp get_disk_usage do
    # This is a placeholder for actual disk usage check
    # In a real implementation, this would use a system command or library
    %{total: "8GB", free: "5GB", used_percent: "37%"}
  end
  
  defp format_search_results(results) do
    # Format the search results for display in a message
    header = "Search Results:\n"
    
    formatted_results = results
    |> Enum.take(5)  # Limit to 5 results to avoid message size limits
    |> Enum.map_join("\n", fn result ->
      "- #{result.title}: #{String.slice(result.summary, 0, 100)}..."
    end)
    
    more_info = "\nFor more details, connect to WiFi AP 'Pendant_Emergency'"
    
    header <> formatted_results <> more_info
  end
end