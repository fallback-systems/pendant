defmodule Pendant.Meshtastic.Handler do
  @moduledoc """
  Handles communication with Meshtastic devices using UART.
  
  This module is responsible for:
  1. Connecting to a Meshtastic device (typically via USB or GPIO pins)
  2. Sending messages to the Meshtastic network
  3. Receiving messages from the Meshtastic network
  4. Broadcasting received messages to interested applications
  """
  
  use GenServer
  require Logger
  
  # The UART speed for Meshtastic devices
  @baud_rate 115200
  # Device ID for this Pendant device
  @device_id "pendant-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  
  # Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Send a message to the Meshtastic network
  """
  def send_message(payload, to_id \\ nil) do
    GenServer.cast(__MODULE__, {:send_message, payload, to_id})
  end
  
  @doc """
  Get the current status of the Meshtastic connection
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  # GenServer Implementation
  
  def init(_opts) do
    # Initialize state
    state = %{
      uart: nil,
      connected: false,
      device: nil,
      pending_messages: [],
      peers: [],
      message_history: []  # Store recent messages
    }
    
    # Start discovery process
    send(self(), :discover_device)
    
    {:ok, state}
  end
  
  def handle_info(:discover_device, state) do
    Logger.info("Discovering Meshtastic devices...")
    
    # List all available UART devices
    {:ok, uart_ports} = Circuits.UART.enumerate()
    
    # Try to find a Meshtastic device
    case find_meshtastic_device(uart_ports) do
      {:ok, device} ->
        # Open connection to the device
        {:ok, uart} = Circuits.UART.start_link()
        
        case Circuits.UART.open(uart, device, speed: @baud_rate, active: true) do
          :ok ->
            Logger.info("Connected to Meshtastic device on #{device}")
            
            # Initialize the device
            # Send configuration commands to the Meshtastic device
            initialize_device(uart)
            
            # Schedule a ping to check connectivity
            Process.send_after(self(), :ping_device, 10_000)
            
            {:noreply, %{state | uart: uart, device: device, connected: true}}
            
          {:error, reason} ->
            Logger.error("Failed to connect to Meshtastic device: #{inspect(reason)}")
            # Retry discovery after a delay
            Process.send_after(self(), :discover_device, 5_000)
            {:noreply, state}
        end
        
      :not_found ->
        Logger.warning("No Meshtastic device found, retrying in 10 seconds")
        # Retry discovery after a delay
        Process.send_after(self(), :discover_device, 10_000)
        {:noreply, state}
    end
  end
  
  def handle_info(:ping_device, %{connected: true, uart: uart} = state) do
    # Send a ping to the device to check if it's still connected
    Circuits.UART.write(uart, "!P\n")
    
    # Schedule next ping
    Process.send_after(self(), :ping_device, 30_000)
    
    {:noreply, state}
  end
  
  def handle_info({:circuits_uart, _port, data}, state) do
    # Process incoming data from the Meshtastic device
    case data do
      {:error, reason} ->
        Logger.error("UART error: #{inspect(reason)}")
        
        # Close the connection and try to reconnect
        if state.uart do
          Circuits.UART.close(state.uart)
        end
        
        # Schedule device rediscovery
        Process.send_after(self(), :discover_device, 5_000)
        
        {:noreply, %{state | connected: false, uart: nil, device: nil}}
        
      _ ->
        # Regular data
        new_state = process_meshtastic_data(data, state)
        {:noreply, new_state}
    end
  end
  
  def handle_cast({:send_message, payload, to_id}, %{connected: true, uart: uart} = state) do
    # Format the message for Meshtastic
    message = format_meshtastic_message(payload, to_id)
    
    # Send the message
    Circuits.UART.write(uart, message)
    
    # Store outgoing message in history
    outgoing_message = %{
      from: "You",
      to: to_id || "broadcast",
      payload: payload,
      timestamp: DateTime.utc_now(),
      type: :outgoing
    }
    
    # Add to message history
    updated_history = [outgoing_message | state.message_history] |> Enum.take(100)
    
    # Broadcast the message to UI subscribers
    Phoenix.PubSub.broadcast(Pendant.PubSub, "meshtastic:messages", {:message, outgoing_message})
    
    {:noreply, %{state | message_history: updated_history}}
  end
  
  def handle_cast({:send_message, payload, to_id}, %{connected: false} = state) do
    # Store the message for later sending when connected
    pending = [{payload, to_id} | state.pending_messages]
    {:noreply, %{state | pending_messages: pending}}
  end
  
  def handle_cast({:store_message, message}, state) do
    # Store message in history, limiting to 100 most recent messages
    updated_history = [message | state.message_history] |> Enum.take(100)
    {:noreply, %{state | message_history: updated_history}}
  end
  
  def handle_call(:status, _from, state) do
    status = %{
      connected: state.connected,
      device: state.device,
      peers: state.peers,
      pending_messages: length(state.pending_messages),
      message_history: state.message_history
    }
    
    {:reply, status, state}
  end
  
  @doc """
  Get the message history
  """
  def get_message_history do
    GenServer.call(__MODULE__, :get_message_history)
  end
  
  def handle_call(:get_message_history, _from, state) do
    {:reply, state.message_history, state}
  end
  
  # Private functions
  
  defp find_meshtastic_device(uart_ports) do
    # Look for devices that match common Meshtastic hardware
    # This is a simplistic approach and might need refinement
    meshtastic_device = Enum.find_value(uart_ports, fn {device, info} ->
      cond do
        # Match ESP32 or other common Meshtastic device IDs
        info[:manufacturer] == "Silicon Labs" -> device
        String.contains?(device, "ttyUSB") -> device  # Linux
        String.contains?(device, "ttyACM") -> device  # Linux
        String.contains?(device, "cu.usbmodem") -> device  # macOS
        true -> nil
      end
    end)
    
    case meshtastic_device do
      nil -> :not_found
      device -> {:ok, device}
    end
  end
  
  defp initialize_device(uart) do
    # Send initialization commands to the Meshtastic device
    # This is a simplified example and would need to be adjusted for actual Meshtastic protocol
    
    # Set device name
    Circuits.UART.write(uart, "!S#{@device_id}\n")
    
    # Request peer list
    Circuits.UART.write(uart, "!L\n")
    
    # Set to router mode
    Circuits.UART.write(uart, "!M3\n")
  end
  
  defp process_meshtastic_data(data, state) do
    # This is a simplified placeholder for actual Meshtastic protocol parsing
    cond do
      # Detect incoming message
      String.starts_with?(data, "!M") ->
        message_data = parse_message(data)
        broadcast_message(message_data)
        state
        
      # Detect peer list update
      String.starts_with?(data, "!L") ->
        peers = parse_peer_list(data)
        %{state | peers: peers}
        
      # Other message types would be handled here
      true ->
        # Unknown message format, log it
        Logger.debug("Unhandled Meshtastic data: #{inspect(data)}")
        state
    end
  end
  
  defp parse_message(data) do
    # Simplified placeholder for actual message parsing
    %{
      from: String.slice(data, 2, 8),
      payload: String.slice(data, 10, 999),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp parse_peer_list(data) do
    # Simplified placeholder for actual peer list parsing
    data
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn peer -> peer != "" end)
  end
  
  defp broadcast_message(message) do
    # Broadcast the message to interested processes
    Phoenix.PubSub.broadcast(Pendant.PubSub, "meshtastic:messages", {:message, message})
    
    # Store the message in the process state for history
    # This would be expanded in a real implementation to persist messages
    GenServer.cast(__MODULE__, {:store_message, message})
    
    # Log the message
    Logger.info("Meshtastic message from #{message.from}: #{message.payload}")
  end
  
  defp format_meshtastic_message(payload, nil) do
    # Broadcast message to all peers
    "!B#{payload}\n"
  end
  
  defp format_meshtastic_message(payload, to_id) do
    # Direct message to specific peer
    "!D#{to_id}:#{payload}\n"
  end
end