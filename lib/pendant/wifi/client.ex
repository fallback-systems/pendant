defmodule Pendant.WiFi.Client do
  @moduledoc """
  Manages WiFi client connectivity for connecting to other Pendant devices.
  
  This module is responsible for:
  1. Scanning for other Pendant WiFi networks
  2. Connecting to other Pendant devices as a client
  3. Managing the WiFi client connection state
  """
  
  use GenServer
  require Logger
  alias VintageNetWiFi
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get the current WiFi client status
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Scan for available WiFi networks
  """
  def scan do
    GenServer.call(__MODULE__, :scan)
  end
  
  @doc """
  Connect to a WiFi network
  """
  def connect(ssid, password \\ nil) do
    GenServer.cast(__MODULE__, {:connect, ssid, password})
  end
  
  @doc """
  Disconnect from the current WiFi network
  """
  def disconnect do
    GenServer.cast(__MODULE__, :disconnect)
  end
  
  # GenServer Implementation
  
  def init(_opts) do
    # Initialize state
    state = %{
      connected: false,
      ssid: nil,
      scan_results: [],
      last_scan: nil,
      connection_info: nil
    }
    
    # Subscribe to VintageNet connection events
    VintageNet.subscribe(["interface", "wlan0", "connection"])
    
    # Schedule periodic scan
    schedule_scan()
    
    {:ok, state}
  end
  
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
  
  def handle_call(:scan, _from, state) do
    # Perform a WiFi scan for Pendant devices
    case VintageNetWiFi.scan("wlan0") do
      {:ok, scan_results} ->
        # Filter to find Pendant devices
        pendant_networks = filter_pendant_networks(scan_results)
        
        # Update state with scan results
        updated_state = %{
          state | 
          scan_results: pendant_networks,
          last_scan: DateTime.utc_now()
        }
        
        {:reply, {:ok, pendant_networks}, updated_state}
        
      {:error, reason} ->
        Logger.error("WiFi scan failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_cast({:connect, ssid, password}, state) do
    Logger.info("Connecting to WiFi network: #{ssid}")
    
    # Create network configuration
    network_config = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: ssid,
            key_mgmt: if(password, do: :wpa_psk, else: :none),
            psk: password
          }
        ]
      },
      ipv4: %{
        method: :dhcp
      }
    }
    
    # Configure the WiFi interface
    :ok = VintageNet.configure("wlan0", network_config)
    
    # Update state (actual connection state will be updated via subscription)
    {:noreply, %{state | ssid: ssid}}
  end
  
  def handle_cast(:disconnect, state) do
    Logger.info("Disconnecting from WiFi network")
    
    # Deconfigure the WiFi interface
    :ok = VintageNet.deconfigure("wlan0")
    
    # Update state (actual connection state will be updated via subscription)
    {:noreply, state}
  end
  
  def handle_info(
    {VintageNet, ["interface", "wlan0", "connection"], _old_value, :connected, _meta},
    state
  ) do
    Logger.info("WiFi connected to #{state.ssid}")
    
    # Get connection information
    connection_info = get_connection_info()
    
    # Update state
    updated_state = %{
      state | 
      connected: true,
      connection_info: connection_info
    }
    
    # Notify P2P manager of connection
    Pendant.P2P.Manager.notify_connection(state.ssid, connection_info)
    
    {:noreply, updated_state}
  end
  
  def handle_info(
    {VintageNet, ["interface", "wlan0", "connection"], _old_value, :disconnected, _meta},
    state
  ) do
    Logger.info("WiFi disconnected")
    
    # Update state
    updated_state = %{
      state | 
      connected: false,
      connection_info: nil
    }
    
    # Notify P2P manager of disconnection
    Pendant.P2P.Manager.notify_disconnection()
    
    {:noreply, updated_state}
  end
  
  def handle_info(:scan_networks, state) do
    # Perform a WiFi scan in the background
    Task.start(fn ->
      case VintageNetWiFi.scan("wlan0") do
        {:ok, scan_results} ->
          # Filter for Pendant devices
          pendant_networks = filter_pendant_networks(scan_results)
          
          # Send the results back to self
          GenServer.cast(__MODULE__, {:update_scan_results, pendant_networks})
          
        {:error, reason} ->
          Logger.warn("Background WiFi scan failed: #{inspect(reason)}")
      end
    end)
    
    # Schedule next scan
    schedule_scan()
    
    {:noreply, state}
  end
  
  def handle_cast({:update_scan_results, scan_results}, state) do
    {:noreply, %{state | scan_results: scan_results, last_scan: DateTime.utc_now()}}
  end
  
  # Private functions
  
  defp filter_pendant_networks(scan_results) do
    # Filter WiFi networks to find Pendant devices
    scan_results
    |> Enum.filter(fn network ->
      # Look for Pendant device SSIDs
      String.contains?(network.ssid, "Pendant_")
    end)
    |> Enum.sort_by(fn network -> 
      # Sort by signal strength (RSSI)
      network.signal_percent
    end, :desc)
  end
  
  defp get_connection_info do
    # Get information about the current connection
    # This is a simplified placeholder
    %{
      ip_address: get_ip_address(),
      gateway: get_gateway(),
      dns: get_dns_servers(),
      connected_at: DateTime.utc_now()
    }
  end
  
  defp get_ip_address do
    # In a real implementation, this would retrieve the actual IP
    # For now, return a placeholder
    "192.168.1.123"
  end
  
  defp get_gateway do
    # In a real implementation, this would retrieve the actual gateway
    # For now, return a placeholder
    "192.168.1.1"
  end
  
  defp get_dns_servers do
    # In a real implementation, this would retrieve the actual DNS servers
    # For now, return placeholders
    ["192.168.1.1", "8.8.8.8"]
  end
  
  defp schedule_scan do
    # Scan for networks every 60 seconds
    Process.send_after(self(), :scan_networks, 60_000)
  end
end