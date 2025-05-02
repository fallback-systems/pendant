defmodule Pendant.Integration.AuthFlowTest do
  use Pendant.ConnCase, async: false
  use Phoenix.ChannelTest
  
  alias Pendant.Chat
  alias Pendant.Auth
  
  @endpoint Pendant.Web.Endpoint
  
  describe "authentication flow" do
    test "complete authentication and authorization journey" do
      # Step 1: Create users with different roles
      {:ok, admin} = Chat.create_user(%{
        username: "admin_user_#{System.unique_integer([:positive])}",
        display_name: "Admin User",
        device_id: "admin_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      {:ok, regular_user} = Chat.create_user(%{
        username: "regular_user_#{System.unique_integer([:positive])}",
        display_name: "Regular User",
        device_id: "regular_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      {:ok, guest_user} = Chat.create_user(%{
        username: "guest_user_#{System.unique_integer([:positive])}",
        display_name: "Guest User",
        device_id: "guest_device_#{System.unique_integer([:positive])}",
        status: "online"
      })
      
      # Step 2: Create rooms with different access levels
      {:ok, public_room} = Chat.create_room(%{
        name: "public_room_#{System.unique_integer([:positive])}",
        room_type: "public",
        description: "Public room accessible to all"
      })
      
      {:ok, private_room} = Chat.create_room(%{
        name: "private_room_#{System.unique_integer([:positive])}",
        room_type: "private",
        description: "Private room for members only"
      })
      
      # Step 3: Set up room memberships with different roles
      # Admin is a member of both rooms with admin role
      {:ok, _} = Chat.add_user_to_room(admin.id, public_room.id, "admin")
      {:ok, _} = Chat.add_user_to_room(admin.id, private_room.id, "admin")
      
      # Regular user is only a member of the private room
      {:ok, _} = Chat.add_user_to_room(regular_user.id, private_room.id, "member")
      
      # Guest user is not a member of any room yet
      
      # Step 4: Generate tokens for all users
      admin_token = Auth.generate_token(admin.id)
      regular_token = Auth.generate_token(regular_user.id)
      guest_token = Auth.generate_token(guest_user.id)
      
      # Step 5: Test token verification
      {:ok, admin_data} = Auth.verify_token(admin_token)
      assert admin_data.user_id == admin.id
      assert "admin" in admin_data.roles
      
      {:ok, regular_data} = Auth.verify_token(regular_token)
      assert regular_data.user_id == regular_user.id
      assert "user" in regular_data.roles
      
      # Step 6: Test room access authorization
      # Admin should have access to both rooms
      assert Auth.can_access_room?(admin.id, public_room.id)
      assert Auth.can_access_room?(admin.id, private_room.id)
      
      # Regular user should have access only to the private room
      refute Auth.can_access_room?(regular_user.id, public_room.id)
      assert Auth.can_access_room?(regular_user.id, private_room.id)
      
      # Guest user should not have access to any room
      refute Auth.can_access_room?(guest_user.id, public_room.id)
      refute Auth.can_access_room?(guest_user.id, private_room.id)
      
      # Step 7: Test API access with authentication
      # Admin should be able to access all rooms
      admin_conn = build_conn()
        |> put_req_header("authorization", "Bearer #{admin_token}")
      
      response = admin_conn
        |> get(Routes.room_path(@endpoint, :show, public_room.id))
        |> json_response(200)
      
      assert response["data"]["id"] == public_room.id
      
      response = admin_conn
        |> get(Routes.room_path(@endpoint, :show, private_room.id))
        |> json_response(200)
        
      assert response["data"]["id"] == private_room.id
      
      # Regular user should only be able to access private room
      regular_conn = build_conn()
        |> put_req_header("authorization", "Bearer #{regular_token}")
      
      # This should fail since regular user is not a member
      regular_conn
        |> get(Routes.room_path(@endpoint, :show, public_room.id))
        |> json_response(403)
      
      # This should succeed
      response = regular_conn
        |> get(Routes.room_path(@endpoint, :show, private_room.id))
        |> json_response(200)
        
      assert response["data"]["id"] == private_room.id
      
      # Step 8: Test socket connections
      {:ok, admin_socket} = connect(Pendant.Web.Socket, %{"token" => admin_token})
      {:ok, regular_socket} = connect(Pendant.Web.Socket, %{"token" => regular_token})
      {:ok, guest_socket} = connect(Pendant.Web.Socket, %{"token" => guest_token})
      
      # Step 9: Test channel join authorization
      # Admin should be able to join both room channels
      {:ok, _, _} = subscribe_and_join(
        admin_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{public_room.id}"
      )
      
      {:ok, _, _} = subscribe_and_join(
        admin_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{private_room.id}"
      )
      
      # Regular user should only be able to join the private room
      {:error, %{reason: "unauthorized"}} = subscribe_and_join(
        regular_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{public_room.id}"
      )
      
      {:ok, _, _} = subscribe_and_join(
        regular_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{private_room.id}"
      )
      
      # Guest user shouldn't be able to join either room
      {:error, %{reason: "unauthorized"}} = subscribe_and_join(
        guest_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{public_room.id}"
      )
      
      {:error, %{reason: "unauthorized"}} = subscribe_and_join(
        guest_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{private_room.id}"
      )
      
      # Step 10: Test changing permissions dynamically
      # Add guest to public room
      {:ok, _} = Chat.add_user_to_room(guest_user.id, public_room.id, "member")
      
      # Guest should now be able to join the public room
      {:ok, _, _} = subscribe_and_join(
        guest_socket,
        Pendant.Web.ChatChannel,
        "chat:room:#{public_room.id}"
      )
      
      # Step 11: Test role verification
      assert Auth.has_role?(admin.id, "admin")
      refute Auth.has_role?(regular_user.id, "admin")
      
      # Step 12: Test token update when roles change
      # The regular user's token should still work even though roles change
      {:ok, _} = Chat.add_user_to_room(regular_user.id, public_room.id, "moderator")
      
      # Verify token should return updated roles
      {:ok, updated_data} = Auth.verify_token(regular_token)
      assert "moderator" in updated_data.roles
    end
  end
end