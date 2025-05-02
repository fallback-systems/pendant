defmodule Pendant.WiFi.AccessPoint do
  @moduledoc """
  Manages the WiFi access point for Pendant devices.
  
  This module is responsible for:
  1. Creating and managing a WiFi access point
  2. Handling client connections to the access point
  3. Providing network services to connected clients
  """
  
  use GenServer
  require Logger
  alias VintageNetWiFi
  
  # Default configuration
  @default_config %{
    ssid: "Pendant_Emergency",
    password: nil,  # Open network for emergency use
    address: "192.168.0.1",
    dhcp_range: {"192.168.0.10", "192.168.0.100"},
    channel: 6
  }
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get the current status of the WiFi access point
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Enable or disable the WiFi access point
  """
  def set_enabled(enabled) do
    GenServer.cast(__MODULE__, {:set_enabled, enabled})
  end
  
  @doc """
  Update the access point configuration
  """
  def update_config(config) do
    GenServer.cast(__MODULE__, {:update_config, config})
  end
  
  @doc """
  Get a list of connected clients
  """
  def connected_clients do
    GenServer.call(__MODULE__, :connected_clients)
  end
  
  # GenServer Implementation
  
  def init(_opts) do
    # Initialize state with default configuration
    state = %{
      config: @default_config,
      active: true,
      clients: [],
      last_check: DateTime.utc_now()
    }
    
    # Start the access point
    configure_access_point(state.config, state.active)
    
    # Schedule periodic client check
    schedule_client_check()
    
    {:ok, state}
  end
  
  def handle_call(:status, _from, state) do
    status = %{
      active: state.active,
      ssid: state.config.ssid,
      channel: state.config.channel,
      client_count: length(state.clients),
      last_check: state.last_check
    }
    
    {:reply, status, state}
  end
  
  def handle_call(:connected_clients, _from, state) do
    {:reply, state.clients, state}
  end
  
  def handle_cast({:set_enabled, enabled}, state) do
    # Only take action if state is changing
    if enabled != state.active do
      configure_access_point(state.config, enabled)
      {:noreply, %{state | active: enabled}}
    else
      {:noreply, state}
    end
  end
  
  def handle_cast({:update_config, new_config}, state) do
    # Merge the new config with the existing one
    updated_config = Map.merge(state.config, new_config)
    
    # Apply the new configuration if AP is active
    if state.active do
      configure_access_point(updated_config, true)
    end
    
    {:noreply, %{state | config: updated_config}}
  end
  
  def handle_info(:check_clients, state) do
    # Check for connected clients
    clients = get_connected_clients()
    
    # Log client changes
    if clients != state.clients do
      Logger.info("WiFi AP clients updated: #{inspect(clients)}")
    end
    
    # Schedule next check
    schedule_client_check()
    
    {:noreply, %{state | clients: clients, last_check: DateTime.utc_now()}}
  end
  
  # Private functions
  
  defp configure_access_point(config, enabled) do
    Logger.info("Configuring WiFi AP: SSID=#{config.ssid}, Enabled=#{enabled}")
    
    ap_config = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            mode: :ap,
            ssid: config.ssid,
            key_mgmt: if(config.password, do: :wpa_psk, else: :none),
            psk: config.password,
            ap_scan: 1,
            frequency: channel_to_frequency(config.channel)
          }
        ]
      },
      ipv4: %{
        method: :static,
        address: config.address,
        prefix_length: 24
      },
      dhcpd: %{
        start: elem(config.dhcp_range, 0),
        end: elem(config.dhcp_range, 1),
        options: %{
          dns: [config.address],
          subnet: {255, 255, 255, 0},
          router: [config.address]
        }
      }
    }
    
    if enabled do
      VintageNet.configure("wlan0", ap_config)
    else
      # If disabling, remove the configuration
      VintageNet.deconfigure("wlan0")
    end
  end
  
  defp get_connected_clients do
    # Get the list of clients from the DHCP leases
    # This is a simplified approach; a real implementation would
    # parse the DHCP lease file or use a more direct method
    
    # In a real implementation, we'd read the DHCP leases file
    # For this example, we'll simulate with some fake data
    [
      %{ip: "192.168.0.10", mac: "aa:bb:cc:dd:ee:ff", hostname: "user-device"},
      %{ip: "192.168.0.11", mac: "11:22:33:44:55:66", hostname: "android-phone"}
    ]
  end
  
  defp schedule_client_check do
    # Check clients every 30 seconds
    Process.send_after(self(), :check_clients, 30_000)
  end
  
  defp channel_to_frequency(channel) do
    # Convert WiFi channel to frequency in MHz
    case channel do
      1 -> 2412
      2 -> 2417
      3 -> 2422
      4 -> 2427
      5 -> 2432
      6 -> 2437
      7 -> 2442
      8 -> 2447
      9 -> 2452
      10 -> 2457
      11 -> 2462
      36 -> 5180  # 5GHz channels
      40 -> 5200
      44 -> 5220
      48 -> 5240
      _ -> 2437   # Default to channel 6
    end
  end
end