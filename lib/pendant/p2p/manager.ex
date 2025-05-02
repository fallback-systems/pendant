defmodule Pendant.P2P.Manager do
  @moduledoc """
  Manages peer-to-peer connections between Pendant devices.
  
  This module is responsible for:
  1. Discovering other Pendant devices on the network
  2. Establishing connections to other devices
  3. Synchronizing knowledge base content between devices
  """
  
  use GenServer
  require Logger
  alias Pendant.WiFi.Client, as: WiFiClient
  alias Pendant.NetworkManager
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Notify the P2P manager of a new WiFi connection
  """
  def notify_connection(ssid, connection_info) do
    GenServer.cast(__MODULE__, {:connected, ssid, connection_info})
  end
  
  @doc """
  Notify the P2P manager of WiFi disconnection
  """
  def notify_disconnection do
    GenServer.cast(__MODULE__, :disconnected)
  end
  
  @doc """
  Get the current P2P connection status
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Manually initiate device discovery
  """
  def discover_devices do
    GenServer.cast(__MODULE__, :discover)
  end
  
  @doc """
  Initiate knowledge base synchronization with peer devices
  """
  def sync_knowledge_base do
    GenServer.cast(__MODULE__, :sync_knowledge)
  end
  
  # GenServer Implementation
  
  def init(_opts) do
    # Initialize state
    state = %{
      mode: :idle,  # :idle, :ap, :client
      connected_to: nil,
      discovered_peers: [],
      last_discovery: nil,
      syncing: false
    }
    
    # Start discovery process after a delay
    Process.send_after(self(), :initial_discovery, 30_000)
    
    {:ok, state}
  end
  
  def handle_info(:initial_discovery, state) do
    # Perform initial device discovery
    Logger.info("Performing initial P2P device discovery")
    send(self(), :discover)
    
    # Schedule periodic discovery
    schedule_discovery()
    
    {:noreply, state}
  end
  
  def handle_info(:discover, state) do
    # Don't perform discovery if we're already connected as a client
    if state.mode != :client do
      Task.start(fn ->
        discover_pendant_devices()
      end)
    end
    
    # Schedule next discovery
    schedule_discovery()
    
    {:noreply, state}
  end
  
  def handle_info(:check_connectivity, state) do
    # Check if we should connect to another device
    new_state = check_and_establish_connections(state)
    
    # Schedule next check
    schedule_connectivity_check()
    
    {:noreply, new_state}
  end
  
  def handle_cast({:connected, ssid, connection_info}, state) do
    Logger.info("P2P: Connected to #{ssid} with IP #{connection_info.ip_address}")
    
    # Update state to reflect client mode
    new_state = %{
      state |
      mode: :client,
      connected_to: %{
        ssid: ssid,
        connection_info: connection_info,
        connected_at: DateTime.utc_now()
      }
    }
    
    # Notify of successful P2P connection
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "p2p:events",
      {:p2p_connected, ssid, connection_info}
    )
    
    # Initiate knowledge base sync
    Process.send_after(self(), :sync_knowledge, 5_000)
    
    {:noreply, new_state}
  end
  
  def handle_cast(:disconnected, %{mode: :client} = state) do
    Logger.info("P2P: Disconnected from #{state.connected_to.ssid}")
    
    # Reset state
    new_state = %{
      state |
      mode: :idle,
      connected_to: nil
    }
    
    # Notify of P2P disconnection
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "p2p:events",
      {:p2p_disconnected}
    )
    
    # Schedule a connectivity check
    Process.send_after(self(), :check_connectivity, 5_000)
    
    {:noreply, new_state}
  end
  
  def handle_cast(:disconnected, state) do
    # We weren't in client mode, so this is a no-op
    {:noreply, state}
  end
  
  def handle_cast(:discover, state) do
    # Manually trigger discovery
    Task.start(fn ->
      peers = discover_pendant_devices()
      GenServer.cast(__MODULE__, {:discovery_results, peers})
    end)
    
    {:noreply, state}
  end
  
  def handle_cast({:discovery_results, peers}, state) do
    Logger.info("P2P: Discovered #{length(peers)} pendant peers")
    
    new_state = %{
      state |
      discovered_peers: peers,
      last_discovery: DateTime.utc_now()
    }
    
    # Notify of discovered peers
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "p2p:events",
      {:p2p_peers_discovered, peers}
    )
    
    # Check if we should connect to any of them
    if state.mode == :idle and !Enum.empty?(peers) do
      Process.send_after(self(), :check_connectivity, 1_000)
    end
    
    {:noreply, new_state}
  end
  
  def handle_cast(:sync_knowledge, state) do
    # Don't sync if we're already syncing
    if state.syncing do
      {:noreply, state}
    else
      # Start knowledge base sync in the background
      Task.start(fn ->
        sync_result = sync_with_peer(state.connected_to)
        GenServer.cast(__MODULE__, {:sync_completed, sync_result})
      end)
      
      {:noreply, %{state | syncing: true}}
    end
  end
  
  def handle_cast({:sync_completed, result}, state) do
    Logger.info("P2P: Knowledge base sync completed: #{inspect(result)}")
    
    # Notify of sync completion
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "p2p:events",
      {:p2p_sync_completed, result}
    )
    
    {:noreply, %{state | syncing: false}}
  end
  
  def handle_call(:status, _from, state) do
    status = %{
      mode: state.mode,
      connected_to: state.connected_to,
      discovered_peers: state.discovered_peers,
      last_discovery: state.last_discovery,
      syncing: state.syncing
    }
    
    {:reply, status, state}
  end
  
  # Private functions
  
  defp discover_pendant_devices do
    # Use WiFiClient to scan for Pendant networks
    case WiFiClient.scan() do
      {:ok, networks} -> 
        # Filter and transform the networks
        networks
        |> Enum.filter(fn network -> 
          String.contains?(network.ssid, "Pendant_")
        end)
        |> Enum.map(fn network ->
          %{
            ssid: network.ssid,
            signal_strength: network.signal_percent,
            channel: network.channel,
            discovered_at: DateTime.utc_now()
          }
        end)
        
      {:error, _reason} ->
        []
    end
  end
  
  defp check_and_establish_connections(state) do
    # Don't try to connect if we're already connected or in AP mode
    if state.mode != :idle or Enum.empty?(state.discovered_peers) do
      state
    else
      # Find the best peer to connect to (strongest signal)
      best_peer = Enum.max_by(state.discovered_peers, fn peer -> peer.signal_strength end)
      
      Logger.info("P2P: Attempting to connect to peer #{best_peer.ssid}")
      
      # Request WiFi client mode
      NetworkManager.switch_to_client_mode(best_peer.ssid)
      
      # Update state to show we're attempting connection
      %{state | mode: :connecting}
    end
  end
  
  defp sync_with_peer(nil), do: {:error, :not_connected}
  defp sync_with_peer(peer) do
    # Attempt to sync knowledge base with the connected peer
    base_url = "http://#{peer.connection_info.gateway}"
    
    Logger.info("P2P: Syncing knowledge base with #{peer.ssid} at #{base_url}")
    
    # Get categories from peer
    with {:ok, categories} <- fetch_peer_data("#{base_url}/api/categories"),
         {:ok, articles} <- fetch_peer_data("#{base_url}/api/articles") do
      
      # Process the peer data (would implement actual sync here)
      sync_count = %{
        categories: length(categories),
        articles: length(articles)
      }
      
      {:ok, sync_count}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp fetch_peer_data(url) do
    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}
        
      {:ok, %{status_code: status}} ->
        {:error, "HTTP error: #{status}"}
        
      {:error, %{reason: reason}} ->
        {:error, "Connection error: #{reason}"}
    end
  end
  
  defp schedule_discovery do
    # Run discovery every 5 minutes
    Process.send_after(self(), :discover, 5 * 60 * 1000)
  end
  
  defp schedule_connectivity_check do
    # Check connectivity every minute
    Process.send_after(self(), :check_connectivity, 60 * 1000)
  end
end