defmodule Pendant.Integration.FileSharingTest do
  use Pendant.ConnCase, async: false
  use Phoenix.ChannelTest
  
  alias Pendant.Chat
  
  @endpoint Pendant.Web.Endpoint
  
  setup do
    # Ensure uploads directory exists
    uploads_dir = "/home/user/dev/pendant/priv/static/uploads"
    File.mkdir_p!(uploads_dir)
    
    on_exit(fn ->
      # Clean up any test files created
      Path.wildcard("#{uploads_dir}/test_file_*") |> Enum.each(&File.rm/1)
      Path.wildcard("#{uploads_dir}/*.tmp") |> Enum.each(&File.rm/1)
    end)
    
    :ok
  end
  
  describe "file sharing flow" do
    test "complete file upload and download journey" do
      # Step 1: Create users and room
      {:ok, user} = Chat.create_user(%{
        username: "file_user_#{System.unique_integer([:positive])}",
        display_name: "File User",
        device_id: "file_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      {:ok, room} = Chat.create_room(%{
        name: "file_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test room for file sharing"
      })
      
      {:ok, _} = Chat.add_user_to_room(user.id, room.id)
      
      # Step 2: Generate a token and connect socket
      token = Pendant.Auth.generate_token(user.id)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Step 3: Join the chat room
      {:ok, _, channel_socket} = subscribe_and_join(
        socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{room.id}"
      )
      
      # Step 4: Create a test file
      test_content = "This is a test file for integration testing #{System.unique_integer([:positive])}"
      test_filename = "test_file_#{System.unique_integer([:positive])}.txt"
      
      # Step 5: Upload the file via the channel
      ref = push(channel_socket, "upload_file", %{
        "file" => %{
          "filename" => test_filename,
          "binary" => test_content
        }
      })
      
      # Step 6: Verify the upload was successful
      assert_reply ref, :ok, reply
      
      # Step 7: Check that the message was created with the right metadata
      assert reply.message_type == "file"
      assert reply.file_name == test_filename
      assert reply.file_size == byte_size(test_content)
      assert reply.file_path =~ "/uploads/"
      
      # Step 8: Verify the file was saved correctly
      file_path = "/home/user/dev/pendant#{reply.file_path}"
      assert File.exists?(file_path)
      assert File.read!(file_path) == test_content
      
      # Step 9: Verify the message is retrievable via the API
      conn = build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(Routes.message_path(@endpoint, :index, room_id: room.id))
      
      # Step 10: Check response includes the file message
      assert json_response(conn, 200)["data"] |> length() >= 1
      
      message = json_response(conn, 200)["data"] |> List.first()
      assert message["message_type"] == "file"
      assert message["file_name"] == test_filename
      
      # Step 11: Try downloading the file using the path
      conn = build_conn()
        |> get(reply.file_path)
      
      # Step 12: Verify download is successful
      assert response(conn, 200) == test_content
      assert get_resp_header(conn, "content-type") == ["text/plain"]
    end
    
    test "enforces file type restrictions" do
      # Step 1: Create user and room
      {:ok, user} = Chat.create_user(%{
        username: "file_user_#{System.unique_integer([:positive])}",
        display_name: "File User",
        device_id: "file_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      {:ok, room} = Chat.create_room(%{
        name: "file_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test room for file restrictions"
      })
      
      {:ok, _} = Chat.add_user_to_room(user.id, room.id)
      
      # Step 2: Generate a token and connect socket
      token = Pendant.Auth.generate_token(user.id)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Step 3: Join the chat room
      {:ok, _, channel_socket} = subscribe_and_join(
        socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{room.id}"
      )
      
      # Step 4: Override allowed extensions for test
      original_allowed = Application.get_env(:pendant, :allowed_file_extensions, [".jpg", ".jpeg", ".png", ".gif", ".pdf", ".txt", ".md", ".json"])
      Application.put_env(:pendant, :allowed_file_extensions, [".jpg", ".png"])
      
      # Step 5: Try to upload a restricted file type
      ref = push(channel_socket, "upload_file", %{
        "file" => %{
          "filename" => "malicious.exe",
          "binary" => "This is not a real executable"
        }
      })
      
      # Step 6: Verify upload was rejected
      assert_reply ref, :error, %{errors: error}
      assert error =~ "File type not allowed"
      
      # Reset allowed extensions
      Application.put_env(:pendant, :allowed_file_extensions, original_allowed)
    end
    
    test "enforces file size limits" do
      # Step 1: Create user and room
      {:ok, user} = Chat.create_user(%{
        username: "file_user_#{System.unique_integer([:positive])}",
        display_name: "File User",
        device_id: "file_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      {:ok, room} = Chat.create_room(%{
        name: "file_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Test room for file size limits"
      })
      
      {:ok, _} = Chat.add_user_to_room(user.id, room.id)
      
      # Step 2: Generate a token and connect socket
      token = Pendant.Auth.generate_token(user.id)
      {:ok, socket} = connect(Pendant.Web.Socket, %{"token" => token})
      
      # Step 3: Join the chat room
      {:ok, _, channel_socket} = subscribe_and_join(
        socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{room.id}"
      )
      
      # Step 4: Override max file size for test
      original_max_size = Application.get_env(:pendant, :max_file_size, 10_485_760)
      Application.put_env(:pendant, :max_file_size, 10) # 10 bytes
      
      # Step 5: Try to upload a file larger than the limit
      ref = push(channel_socket, "upload_file", %{
        "file" => %{
          "filename" => "too_large.txt",
          "binary" => String.duplicate("x", 20) # 20 bytes
        }
      })
      
      # Step 6: Verify upload was rejected
      assert_reply ref, :error, %{errors: error}
      assert error =~ "exceeds maximum allowed size"
      
      # Reset max file size
      Application.put_env(:pendant, :max_file_size, original_max_size)
    end
  end
end