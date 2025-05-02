defmodule Pendant.FileHandlingTest do
  use Pendant.DataCase, async: false
  
  alias Pendant.Chat
  
  setup do
    user = create_test_user()
    room = create_test_room()
    add_user_to_room(user, room)
    
    # Ensure uploads directory exists
    uploads_dir = "/home/user/dev/pendant/priv/static/uploads"
    File.mkdir_p!(uploads_dir)
    
    on_exit(fn ->
      # Clean up any test files created
      Path.wildcard("#{uploads_dir}/test_file_*") |> Enum.each(&File.rm/1)
      Path.wildcard("#{uploads_dir}/*.tmp") |> Enum.each(&File.rm/1)
    end)
    
    # Create a simple test file
    test_file_content = "This is a test file content."
    
    {:ok, %{
      user: user, 
      room: room, 
      uploads_dir: uploads_dir,
      test_file_content: test_file_content
    }}
  end
  
  describe "create_file_message/3" do
    test "successfully creates a file message with valid file", %{user: user, room: room, test_file_content: content} do
      # Prepare file params
      file_params = %{
        filename: "test_file_#{System.unique_integer([:positive])}.txt",
        binary: content
      }
      
      assert {:ok, message} = Chat.create_file_message(room.id, user.id, file_params)
      
      # Validate the created message
      assert message.message_type == "file"
      assert message.room_id == room.id
      assert message.user_id == user.id
      assert message.file_name == file_params.filename
      assert message.file_size == byte_size(content)
      assert message.file_type == "text/plain"
      assert message.file_path =~ "/uploads/"
      
      # Verify the file was actually saved
      assert File.exists?("/home/user/dev/pendant#{message.file_path}")
      assert File.read!("/home/user/dev/pendant#{message.file_path}") == content
    end
    
    test "rejects file that exceeds maximum size", %{user: user, room: room} do
      # Override max file size for test
      original_max_size = Application.get_env(:pendant, :max_file_size, 10_485_760)
      Application.put_env(:pendant, :max_file_size, 10) # 10 bytes
      
      # Prepare file params with content larger than the max
      file_params = %{
        filename: "large_test_file.txt",
        binary: String.duplicate("x", 20) # 20 bytes
      }
      
      assert {:error, message} = Chat.create_file_message(room.id, user.id, file_params)
      assert message =~ "exceeds maximum allowed size"
      
      # Reset the max file size
      Application.put_env(:pendant, :max_file_size, original_max_size)
    end
    
    test "rejects file with disallowed extension", %{user: user, room: room, test_file_content: content} do
      # Override allowed extensions for test
      original_allowed = Application.get_env(:pendant, :allowed_file_extensions, [".jpg", ".jpeg", ".png", ".gif", ".pdf", ".txt", ".md", ".json"])
      Application.put_env(:pendant, :allowed_file_extensions, [".jpg", ".png"])
      
      # Prepare file params with disallowed extension
      file_params = %{
        filename: "test_file.exe",
        binary: content
      }
      
      assert {:error, message} = Chat.create_file_message(room.id, user.id, file_params)
      assert message =~ "File type not allowed"
      
      # Reset allowed extensions
      Application.put_env(:pendant, :allowed_file_extensions, original_allowed)
    end
    
    test "handles missing filename gracefully", %{user: user, room: room, test_file_content: content} do
      # Prepare file params without filename
      file_params = %{
        binary: content
      }
      
      assert {:ok, message} = Chat.create_file_message(room.id, user.id, file_params)
      
      # Should use a default filename
      assert message.file_name == "unnamed_file"
    end
    
    test "sanitizes filenames with invalid characters", %{user: user, room: room, test_file_content: content} do
      # Prepare file params with a filename containing invalid characters
      file_params = %{
        filename: "test/../../../file with spaces & special chars!.txt",
        binary: content
      }
      
      assert {:ok, message} = Chat.create_file_message(room.id, user.id, file_params)
      
      # The stored filename should be sanitized
      assert message.file_name == file_params.filename
      
      # The file path should be sanitized and not contain the malicious path traversal
      refute message.file_path =~ "../"
      refute message.file_path =~ "spaces & special"
      assert message.file_path =~ "test___file_with_spaces___special_chars_"
    end
  end
  
  describe "write_file_safely/2" do
    # This is a private function, so we'll test it through the create_file_message function
    
    test "writes file content correctly", %{user: user, room: room, test_file_content: content} do
      # Prepare file params
      file_params = %{
        filename: "test_file_#{System.unique_integer([:positive])}.txt",
        binary: content
      }
      
      assert {:ok, message} = Chat.create_file_message(room.id, user.id, file_params)
      
      # Verify the file content
      assert File.read!("/home/user/dev/pendant#{message.file_path}") == content
    end
    
    test "handles binary data correctly", %{user: user, room: room} do
      # Create some binary data (simulating an image)
      binary_data = :crypto.strong_rand_bytes(1000)
      
      # Prepare file params
      file_params = %{
        filename: "test_binary_#{System.unique_integer([:positive])}.bin",
        binary: binary_data
      }
      
      assert {:ok, message} = Chat.create_file_message(room.id, user.id, file_params)
      
      # Verify the file content matches the original binary data
      assert File.read!("/home/user/dev/pendant#{message.file_path}") == binary_data
    end
    
    test "creates unique filenames for each upload", %{user: user, room: room, test_file_content: content} do
      # Upload the same file twice
      file_params = %{
        filename: "duplicate_test.txt",
        binary: content
      }
      
      assert {:ok, message1} = Chat.create_file_message(room.id, user.id, file_params)
      assert {:ok, message2} = Chat.create_file_message(room.id, user.id, file_params)
      
      # The file paths should be different
      assert message1.file_path != message2.file_path
      
      # Both files should exist
      assert File.exists?("/home/user/dev/pendant#{message1.file_path}")
      assert File.exists?("/home/user/dev/pendant#{message2.file_path}")
    end
  end
  
  describe "format_file_size/1" do
    # This is a private function, but we can still test its functionality indirectly
    
    test "handles uploading files of different sizes", %{user: user, room: room} do
      # Test a very small file (bytes)
      small_content = "abc"
      small_params = %{
        filename: "small_file.txt",
        binary: small_content
      }
      
      # Test a medium file (KB)
      medium_content = String.duplicate("x", 2000)
      medium_params = %{
        filename: "medium_file.txt",
        binary: medium_content
      }
      
      # Test a larger file (MB) if memory permits
      # This is optional and depends on the test environment
      # large_content = String.duplicate("x", 2_000_000)
      # large_params = %{
      #   filename: "large_file.txt",
      #   binary: large_content
      # }
      
      # Upload the files
      assert {:ok, small_message} = Chat.create_file_message(room.id, user.id, small_params)
      assert {:ok, medium_message} = Chat.create_file_message(room.id, user.id, medium_params)
      # assert {:ok, large_message} = Chat.create_file_message(room.id, user.id, large_params)
      
      # Verify the sizes are correctly stored
      assert small_message.file_size == byte_size(small_content)
      assert medium_message.file_size == byte_size(medium_content)
      # assert large_message.file_size == byte_size(large_content)
      
      # Verify the files exist and have the right content
      assert File.read!("/home/user/dev/pendant#{small_message.file_path}") == small_content
      assert File.read!("/home/user/dev/pendant#{medium_message.file_path}") == medium_content
      # assert File.read!("/home/user/dev/pendant#{large_message.file_path}") == large_content
    end
  end
end