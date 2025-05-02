defmodule Pendant.NetworkManager do
  @moduledoc """
  Manages the network mode of the Pendant device.
  
  This module is responsible for:
  1. Coordinating between WiFi AP and client modes
  2. Managing network mode transitions
  3. Providing network status information
  """
  
  use GenServer
  require Logger
  alias Pendant.WiFi.AccessPoint
  alias Pendant.WiFi.Client, as: WiFiClient
  
  # Network modes
  @mode_ap :access_point      # Device acts as WiFi access point
  @mode_client :wifi_client   # Device connects to another AP
  @mode_dual :dual_mode       # Device operates in both modes (if supported)
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get the current network mode and status
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Switch to access point mode
  """
  def switch_to_ap_mode do
    GenServer.call(__MODULE__, {:switch_mode, @mode_ap})
  end
  
  @doc """
  Switch to client mode
  """
  def switch_to_client_mode(ssid, password \\ nil) do
    GenServer.call(__MODULE__, {:switch_mode, @mode_client, %{ssid: ssid, password: password}})
  end
  
  @doc """
  Try to enable dual mode (if hardware supports it)
  """
  def try_dual_mode do
    GenServer.call(__MODULE__, {:switch_mode, @mode_dual})
  end
  
  # GenServer Implementation
  
  def init(_opts) do
    # Start in AP mode by default
    state = %{
      current_mode: @mode_ap,
      supports_dual_mode: false,  # Set based on hardware capabilities
      ap_status: nil,
      client_status: nil,
      last_mode_change: DateTime.utc_now()
    }
    
    # Schedule status update
    Process.send_after(self(), :update_status, 5_000)
    
    {:ok, state}
  end
  
  def handle_call(:status, _from, state) do
    # Return current network status
    {:reply, state, state}
  end
  
  def handle_call({:switch_mode, @mode_ap}, _from, state) do
    Logger.info("NetworkManager: Switching to AP mode")
    
    # Disable client mode if currently active
    if state.current_mode == @mode_client or state.current_mode == @mode_dual do
      WiFiClient.disconnect()
    end
    
    # Enable AP mode
    AccessPoint.set_enabled(true)
    
    # Update state
    new_state = %{
      state |
      current_mode: @mode_ap,
      last_mode_change: DateTime.utc_now()
    }
    
    # Notify mode change
    notify_mode_change(@mode_ap)
    
    {:reply, :ok, new_state}
  end
  
  def handle_call({:switch_mode, @mode_client, connection_info}, _from, state) do
    Logger.info("NetworkManager: Switching to client mode, connecting to #{connection_info.ssid}")
    
    # Disable AP mode if hardware doesn't support dual mode
    unless state.supports_dual_mode do
      AccessPoint.set_enabled(false)
    end
    
    # Connect to the specified network
    WiFiClient.connect(connection_info.ssid, connection_info.password)
    
    # Update state
    new_state = %{
      state |
      current_mode: if(state.supports_dual_mode, do: @mode_dual, else: @mode_client),
      last_mode_change: DateTime.utc_now()
    }
    
    # Notify mode change
    notify_mode_change(new_state.current_mode)
    
    {:reply, :ok, new_state}
  end
  
  def handle_call({:switch_mode, @mode_dual}, _from, state) do
    if state.supports_dual_mode do
      Logger.info("NetworkManager: Enabling dual mode (AP + Client)")
      
      # Enable both AP and client modes
      AccessPoint.set_enabled(true)
      
      # Don't disconnect client if already connected
      
      # Update state
      new_state = %{
        state |
        current_mode: @mode_dual,
        last_mode_change: DateTime.utc_now()
      }
      
      # Notify mode change
      notify_mode_change(@mode_dual)
      
      {:reply, :ok, new_state}
    else
      Logger.warning("NetworkManager: Dual mode requested but not supported by hardware")
      {:reply, {:error, :not_supported}, state}
    end
  end
  
  def handle_info(:update_status, state) do
    # Get current AP and client status
    ap_status = AccessPoint.status()
    client_status = WiFiClient.status()
    
    # Update state with current status
    new_state = %{
      state |
      ap_status: ap_status,
      client_status: client_status
    }
    
    # Schedule next status update
    Process.send_after(self(), :update_status, 30_000)
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp notify_mode_change(mode) do
    # Notify interested processes of the mode change
    Phoenix.PubSub.broadcast(
      Pendant.PubSub,
      "network:events",
      {:network_mode_changed, mode}
    )
  end
end