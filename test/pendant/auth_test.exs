defmodule Pendant.AuthTest do
  use Pendant.DataCase, async: true
  alias Pendant.Auth
  
  describe "generate_token/1" do
    test "generates a valid token with user id" do
      user = create_test_user()
      token = Auth.generate_token(user.id)
      
      assert is_binary(token)
      assert String.length(token) > 0
      
      # Verify the token decodes back to user data
      {:ok, decoded} = Auth.verify_token(token)
      assert decoded.user_id == user.id
      assert "user" in decoded.roles
    end
    
    test "generates a different token each time" do
      user = create_test_user()
      token1 = Auth.generate_token(user.id)
      token2 = Auth.generate_token(user.id)
      
      assert token1 != token2
    end
    
    test "includes user roles in token" do
      user = create_test_user()
      room = create_test_room()
      add_user_to_room(user, room, "admin")
      
      token = Auth.generate_token(user.id)
      {:ok, decoded} = Auth.verify_token(token)
      
      assert "user" in decoded.roles
      assert "admin" in decoded.roles
    end
  end
  
  describe "verify_token/1" do
    test "returns ok for valid token" do
      user = create_test_user()
      token = Auth.generate_token(user.id)
      
      assert {:ok, _decoded} = Auth.verify_token(token)
    end
    
    test "returns error for invalid token" do
      assert {:error, _reason} = Auth.verify_token("invalid_token")
    end
    
    test "returns error for expired token" do
      # To test token expiration we would need to create a token with a very short expiry
      # and wait for it to expire, but that's not practical in unit tests.
      # Instead we can use Phoenix.Token's API directly to create a token that's already expired.
      
      user = create_test_user()
      
      # Create a token that's already expired (created 1 day + 1 second ago)
      token = Phoenix.Token.sign(
        Pendant.Web.Endpoint,
        Application.get_env(:pendant, :signing_salt, "pendant_secure_salt"),
        %{
          user_id: user.id,
          roles: ["user"],
          created_at: (DateTime.utc_now() |> DateTime.to_unix()) - 86401
        },
        max_age: 86400 # 1 day
      )
      
      assert {:error, :expired} = Auth.verify_token(token)
    end
    
    test "returns error if user no longer exists" do
      user = create_test_user()
      token = Auth.generate_token(user.id)
      
      # Delete the user
      Repo.delete(user)
      
      assert {:error, :user_not_found} = Auth.verify_token(token)
    end
    
    test "updates roles if they've changed since token was issued" do
      user = create_test_user()
      token = Auth.generate_token(user.id)
      
      # Verify initial token
      {:ok, decoded1} = Auth.verify_token(token)
      assert decoded1.roles == ["user"]
      
      # Add user to a room with admin role
      room = create_test_room()
      add_user_to_room(user, room, "admin")
      
      # Verify token again - roles should be updated
      {:ok, decoded2} = Auth.verify_token(token)
      assert "admin" in decoded2.roles
    end
  end
  
  describe "can_access_room?/2" do
    test "returns true if user is a member of the room" do
      user = create_test_user()
      room = create_test_room()
      add_user_to_room(user, room)
      
      assert Auth.can_access_room?(user.id, room.id)
    end
    
    test "returns false if user is not a member of the room" do
      user = create_test_user()
      room = create_test_room()
      
      refute Auth.can_access_room?(user.id, room.id)
    end
    
    test "returns true if user has admin role" do
      user = create_test_user()
      room1 = create_test_room()
      room2 = create_test_room()
      
      # Add user to room1 with admin role
      add_user_to_room(user, room1, "admin")
      
      # User should be able to access both rooms due to admin role
      assert Auth.can_access_room?(user.id, room1.id)
      assert Auth.can_access_room?(user.id, room2.id)
    end
  end
  
  describe "can_modify_crdt?/2" do
    test "returns true if user is a member of the room" do
      user = create_test_user()
      room = create_test_crdt_room()
      add_user_to_room(user, room)
      
      assert Auth.can_modify_crdt?(user.id, room.id)
    end
    
    test "returns false if user is not a member of the room" do
      user = create_test_user()
      room = create_test_crdt_room()
      
      refute Auth.can_modify_crdt?(user.id, room.id)
    end
  end
  
  describe "has_role?/2" do
    test "returns true if user has the role" do
      user = create_test_user()
      room = create_test_room()
      add_user_to_room(user, room, "admin")
      
      assert Auth.has_role?(user.id, "admin")
      assert Auth.has_role?(user.id, "user") # Default role
    end
    
    test "returns false if user doesn't have the role" do
      user = create_test_user()
      
      refute Auth.has_role?(user.id, "admin")
      assert Auth.has_role?(user.id, "user") # Default role
    end
    
    test "returns false for non-existent user" do
      refute Auth.has_role?(999_999, "admin")
      refute Auth.has_role?(999_999, "user")
    end
  end
  
  describe "get_user_roles/1" do
    test "returns list of user roles" do
      user = create_test_user()
      room1 = create_test_room()
      room2 = create_test_room()
      
      add_user_to_room(user, room1, "admin")
      add_user_to_room(user, room2, "moderator")
      
      roles = Auth.get_user_roles(user.id)
      
      assert "user" in roles
      assert "admin" in roles
      assert "moderator" in roles
      assert length(roles) == 3
    end
    
    test "returns only default role for user with no room roles" do
      user = create_test_user()
      
      roles = Auth.get_user_roles(user.id)
      
      assert roles == ["user"]
    end
    
    test "returns empty list for non-existent user" do
      roles = Auth.get_user_roles(999_999)
      
      assert roles == []
    end
  end
  
  describe "create_demo_user/1" do
    test "creates a new user with the given username" do
      username = "demo_user_#{System.unique_integer([:positive])}"
      
      # Override environment for test
      mix_env = Application.get_env(:mix, :env)
      Application.put_env(:mix, :env, :dev)
      
      user = Auth.create_demo_user(username)
      
      assert user.username == username
      assert user.display_name =~ "Demo User"
      assert user.device_id =~ "demo_"
      assert user.status == "online"
      
      # Reset environment
      Application.put_env(:mix, :env, mix_env)
    end
    
    test "returns existing user if username already exists" do
      username = "demo_user_#{System.unique_integer([:positive])}"
      
      # Override environment for test
      mix_env = Application.get_env(:mix, :env)
      Application.put_env(:mix, :env, :dev)
      
      user1 = Auth.create_demo_user(username)
      user2 = Auth.create_demo_user(username)
      
      assert user1.id == user2.id
      
      # Reset environment
      Application.put_env(:mix, :env, mix_env)
    end
    
    test "returns error in production environment" do
      # Override environment for test
      mix_env = Application.get_env(:mix, :env)
      Application.put_env(:mix, :env, :prod)
      
      result = Auth.create_demo_user("demo_user")
      
      assert result == {:error, :not_allowed_in_production}
      
      # Reset environment
      Application.put_env(:mix, :env, mix_env)
    end
  end
end