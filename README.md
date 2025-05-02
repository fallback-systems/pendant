# Pendant - Emergency Communication Device

DO NOT USE THIS YET... WORK IN PROGRESS!

# About

Pendant is an Elixir/Nerves-based emergency communication device designed for scenarios where traditional communication infrastructure (cell towers, internet) is unavailable. It leverages Meshtastic for long-range device-to-device communication and provides a local knowledge base accessible via WiFi.

## Features

- **Meshtastic Integration**: Communicates with other Meshtastic-compatible devices for long-range, low-power messaging
- **WiFi Access Point**: Creates a WiFi hotspot allowing nearby devices to connect
- **Emergency Knowledge Base**: Provides access to essential survival and emergency information
- **P2P Device Connections**: Can connect to other Pendant devices to share and synchronize data
- **Offline Operation**: Designed to work completely offline when infrastructure is unavailable
- **Local Chat System**: Enables communications between devices connected to the same network
- **File Sharing**: Allows users to share important documents and images
- **Collaborative Editing**: Supports CRDTs for conflict-free collaborative document editing

## Hardware Requirements

- Raspberry Pi 4 (or compatible hardware)
- Meshtastic-compatible radio module (e.g., LILYGO® TTGO T-Beam, Heltec WiFi LoRa 32)
- MicroSD card (8GB+ recommended)
- Power source (battery with appropriate capacity for extended use)

## Getting Started

### Building the Firmware

```bash
# Set the target (RPI4 in this example)
export MIX_TARGET=rpi4

# Get dependencies
mix deps.get

# Create the firmware
mix firmware

# Burn to an SD card
mix burn
```

### Hardware Setup

1. Connect the Meshtastic device to the Raspberry Pi via USB or GPIO pins
2. Insert the SD card into the Raspberry Pi
3. Power on the device
4. Look for the "Pendant_Emergency" WiFi network on your phone/laptop
5. Connect to the network and navigate to "pendant.local" in your browser

## Usage

### Web Interface

After connecting to the Pendant's WiFi network, you can access the web interface at `http://pendant.local` or `http://192.168.0.1`. This interface provides:

- Access to the emergency knowledge base
- System status information
- Network configuration options
- Meshtastic message interface
- Local chat system with file transfer capabilities
- Collaborative document editing using CRDTs

### Meshtastic Communication

Pendant can communicate with other Meshtastic devices in range. The system provides multiple ways to send and receive messages:

#### Web Interface

The web interface at `/meshtastic` provides:
- Real-time messaging to all connected Meshtastic devices
- Message history
- Peer selection for direct messaging
- Status monitoring

#### API Endpoints

For programmatic access:
- `POST /api/messages` - Send a message
  - Parameters: `message` (required), `to` (optional peer ID)
- `GET /api/messages/history` - Get message history
- `GET /api/messages/status` - Check Meshtastic connection status

#### CLI Commands

Commands available through Meshtastic CLI:
- `!ping` - Check connection
- `!status` - Get system status
- `!help` - Show available commands
- `!info` - Show device information
- `!search [query]` - Search the knowledge base
- `!network` - Show network status

## Knowledge Base

The knowledge base contains essential emergency information organized by categories. This information is accessible even when internet access is unavailable. The knowledge base can be synchronized between Pendant devices when they connect.

To seed the knowledge base with sample data (for development):

```bash
mix run scripts/seed_knowledge_base.ex
```

The sample data includes emergency information about first aid, water purification, shelter building, and navigation.

## P2P Operation

When multiple Pendant devices are in proximity, they can automatically discover and connect to each other to share and synchronize their knowledge bases, ensuring the most up-to-date information is available across all devices.

## Chat System

The Pendant device includes a powerful local chat system accessible at `/chat`. This system enables:

- Real-time messaging between users connected to the WiFi network
- File sharing for important documents and images
- Collaborative editing with conflict-free replication (CRDTs)
- P2P synchronization when multiple Pendant devices connect

### API Endpoints

The chat system also provides REST API endpoints for programmatic access:

- `POST /api/chat/users` - Create a new user
- `GET /api/chat/rooms` - List all public rooms
- `POST /api/chat/rooms` - Create a new room
- `POST /api/chat/rooms/:room_id/join` - Join a room
- `GET /api/chat/rooms/:room_id/messages` - Get messages from a room
- `POST /api/chat/rooms/:room_id/messages` - Send a message to a room
- `GET /api/chat/rooms/:room_id/crdt` - Get CRDT data for a room
- `POST /api/chat/rooms/:room_id/crdt` - Update CRDT data

### CRDT Support

The chat system uses the `delta_crdt` library to implement efficient Delta-State CRDTs with the following types:

- **Document** - Collaborative text editing with efficient delta synchronization
- **Counter** - Shared counters that can be incremented/decremented
- **Set** - Shared set of items that can be added/removed
- **LWW** - Last-Write-Wins register for single values
- **Map** - Complex nested data structures with conflict resolution

Delta-State CRDTs improve efficiency by only transmitting changes (deltas) rather than entire states, making them much more bandwidth-efficient for emergency scenarios.

## Development

To set up a development environment:

```bash
# Clone the repository
git clone https://github.com/your-username/pendant.git
cd pendant

# Get dependencies
mix deps.get

# Run in host mode (some hardware-specific features will be simulated)
mix run
```

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
