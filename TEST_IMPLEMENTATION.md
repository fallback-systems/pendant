# Pendant Test Implementation

This document provides an overview of the test implementation for the Pendant emergency communication device.

## Test Suite Implementation

A comprehensive test suite has been developed for the Pendant project, covering all major components:

### 1. Auth Module Tests

The auth module tests (`test/pendant/auth_test.exs`) verify:
- Token generation with proper claims
- Token verification and rejection of invalid tokens
- Role-based access control
- Room access authorization
- CRDT modification permissions

Example test:
```elixir
test "returns true if user has the role" do
  user = create_test_user()
  room = create_test_room()
  add_user_to_room(user, room, "admin")
  
  assert Auth.has_role?(user.id, "admin")
  assert Auth.has_role?(user.id, "user") # Default role
end
```

### 2. Rate Limiter Tests

The rate limiter tests (`test/pendant/rate_limiter_test.exs`) verify:
- Token bucket algorithm implementation
- Rate limiting of operations that exceed thresholds
- Different buckets for different clients and operations
- Token refill over time

Example test:
```elixir
test "rejects operations when over the limit" do
  client_id = "test_client"
  operation = "test_operation"
  
  # Perform many operations to exhaust the bucket
  bucket = RateLimiter.get_bucket(client_id, operation)
  max_operations = bucket.max_tokens

  for _ <- 1..max_operations do
    assert {:ok, _} = RateLimiter.check_rate_limit(client_id, operation)
  end
  
  # Next operation should be rejected
  assert {:error, :rate_limited} = RateLimiter.check_rate_limit(client_id, operation)
end
```

### 3. CRDT Tests 

The CRDT tests (`test/pendant/chat/crdt_manager_test.exs`) verify:
- Add, remove, and update operations on CRDTs
- Error handling in CRDT operations
- CRDT state persistence to database
- Delta merging across nodes

Example test:
```elixir
test "adds an item to a set" do
  operation = %{type: "add", key: "items", value: "item1"}
  
  assert {:ok, "item1"} = CRDTManager.update_crdt(room.id, operation)
  
  # Check that the item is in the CRDT
  {:ok, data} = CRDTManager.get_crdt_data(room.id)
  assert data["items"] == "item1"
end
```

### 4. Chat Module Tests

The chat module tests (`test/pendant/chat_test.exs`) verify:
- User management (create, update, status)
- Room management (create, update, join, leave)
- Message operations (create, list, paginate)
- CRDT interactions
- Error handling

Example test:
```elixir
test "list_room_messages/3 returns messages with pagination" do
  # Create 10 messages
  for i <- 1..10 do
    Chat.create_message(%{
      content: "Message #{i}",
      user_id: user.id,
      room_id: room.id
    })
  end
  
  # Get first page (5 messages)
  result = Chat.list_room_messages(room.id, 5)
  
  assert %{messages: messages, cursor: cursor, has_more: has_more} = result
  assert length(messages) == 5
  assert cursor != nil
  assert has_more == true
end
```

### 5. File Handling Tests

The file handling tests (`test/pendant/file_handling_test.exs`) verify:
- File upload validation
- File size restrictions
- File type restrictions
- Secure file naming and storage
- Error handling for invalid files

Example test:
```elixir
test "rejects file with disallowed extension" do
  # Override allowed extensions for test
  Application.put_env(:pendant, :allowed_file_extensions, [".jpg", ".png"])
  
  # Prepare file params with disallowed extension
  file_params = %{
    filename: "test_file.exe",
    binary: "malicious content"
  }
  
  assert {:error, message} = Chat.create_file_message(room.id, user.id, file_params)
  assert message =~ "File type not allowed"
end
```

### 6. Channel Tests

The channel tests verify:
- Socket authentication
- Channel joining with authorization
- Message sending and receiving
- CRDT operations through channels
- File uploads through channels
- Rate limiting of channel operations

Example test:
```elixir
test "creates a new message" do
  # Push a new message
  content = "Test message"
  ref = push(channel_socket, "new_message", %{"content" => content})
  
  # Wait for reply
  assert_reply ref, :ok, reply
  
  # Check reply
  assert Map.has_key?(reply, :id)
  assert reply.content == content
  assert reply.message_type == "text"
end
```

### 7. Integration Tests

The integration tests verify end-to-end workflows:
- Authentication flows
- Complete chat experience
- File sharing
- CRDT collaborative editing

Example test:
```elixir
test "full user journey through chat system" do
  # Create users, connect sockets, join room...
  
  # Alice sends a message
  alice_message = "Hello from Alice!"
  ref = push(alice_chat_socket, "new_message", %{"content" => alice_message})
  assert_reply ref, :ok, _
  
  # Bob should receive Alice's message
  assert_broadcast(:new_message, %{content: ^alice_message})
  
  # Bob sends a reply
  bob_message = "Hello from Bob!"
  ref = push(bob_chat_socket, "new_message", %{"content" => bob_message})
  assert_reply ref, :ok, _
  
  # Alice should receive Bob's message
  assert_broadcast(:new_message, %{content: ^bob_message})
end
```

## Test Structure

The tests are organized in a hierarchical structure:

```
test/
├── pendant/              # Unit tests
│   ├── auth_test.exs
│   ├── rate_limiter_test.exs
│   ├── chat_test.exs
│   ├── file_handling_test.exs
│   ├── chat/
│   │   └── crdt_manager_test.exs
│   └── web/
│       └── channels/
│           ├── socket_test.exs
│           └── chat_channel_test.exs
├── integration/          # Integration tests
│   ├── auth_flow_test.exs
│   ├── chat_flow_test.exs
│   └── file_sharing_test.exs
├── support/              # Test support files
│   ├── conn_case.ex
│   ├── channel_case.ex
│   └── data_case.ex
└── test_helper.exs       # Test configuration
```

## Test Helpers

The test helpers provide common functions for creating test data:

```elixir
def create_test_user(attrs \\ %{}) do
  {:ok, user} = 
    attrs
    |> Enum.into(%{
      username: "test_user_#{System.unique_integer([:positive])}",
      display_name: "Test User",
      device_id: "test_device_#{System.unique_integer([:positive])}",
      status: "online"
    })
    |> Pendant.Chat.create_user()
    
  user
end

def create_test_room(attrs \\ %{}) do
  {:ok, room} =
    attrs
    |> Enum.into(%{
      name: "test_room_#{System.unique_integer([:positive])}",
      room_type: "public",
      description: "Test room description"
    })
    |> Pendant.Chat.create_room()
    
  room
end
```

## Test Database

Tests use an in-memory SQLite database with the schema defined in `test/support/schema.ex`. The database is reset for each test to ensure isolation:

```elixir
# Start the test database with test configuration
Application.put_env(:pendant, Pendant.KnowledgeBase.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "/home/user/dev/pendant/pendant_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10)

# Create schema for testing
Pendant.Test.Schema.drop()
Pendant.Test.Schema.create()
```

## Future Test Enhancements

For a more comprehensive test suite in a production environment, consider adding:

1. **Property-based tests** for CRDT operations to verify conflict resolution
2. **Load tests** to verify performance under emergency conditions
3. **Security tests** to verify proper input sanitization and authorization
4. **Concurrency tests** to verify behavior under simultaneous user actions
5. **Network partition tests** to verify behavior in limited connectivity scenarios