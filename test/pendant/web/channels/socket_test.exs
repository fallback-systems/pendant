defmodule Pendant.Web.SocketTest do
  use Pendant.ChannelCase, async: true
  
  alias Pendant.Web.Socket
  
  describe "connect/3" do
    test "authenticates with valid token" do
      # Create a test user
      user = create_test_user()
      
      # Generate a token
      token = create_test_token(user)
      
      # Connect with the token
      assert {:ok, socket} = connect(Socket, %{"token" => token})
      
      # Check that the user_id is assigned to the socket
      assert socket.assigns.user_id == user.id
      
      # Check that roles are assigned
      assert "user" in socket.assigns.roles
    end
    
    test "rejects connection with invalid token in production" do
      # Save original environment
      original_env = Mix.env()
      
      try do
        # Set environment to production
        Application.put_env(:mix, :env, :prod)
        
        # Try to connect with invalid token
        assert :error = connect(Socket, %{"token" => "invalid_token"})
      after
        # Restore original environment
        Application.put_env(:mix, :env, original_env)
      end
    end
    
    test "creates demo user in development when token is invalid" do
      # Save original environment
      original_env = Mix.env()
      
      try do
        # Set environment to development
        Application.put_env(:mix, :env, :dev)
        
        # Try to connect with invalid token
        assert {:ok, socket} = connect(Socket, %{"token" => "invalid_token"})
        
        # Should have assigned a user_id
        assert socket.assigns.user_id != nil
        
        # Should have assigned guest role
        assert "guest" in socket.assigns.roles
      after
        # Restore original environment
        Application.put_env(:mix, :env, original_env)
      end
    end
    
    test "creates demo user in development when no token is provided" do
      # Save original environment
      original_env = Mix.env()
      
      try do
        # Set environment to development
        Application.put_env(:mix, :env, :dev)
        
        # Try to connect without token
        assert {:ok, socket} = connect(Socket, %{})
        
        # Should have assigned a user_id
        assert socket.assigns.user_id != nil
        
        # Should have assigned guest role
        assert "guest" in socket.assigns.roles
      after
        # Restore original environment
        Application.put_env(:mix, :env, original_env)
      end
    end
    
    test "rejects connection without token in production" do
      # Save original environment
      original_env = Mix.env()
      
      try do
        # Set environment to production
        Application.put_env(:mix, :env, :prod)
        
        # Try to connect without token
        assert :error = connect(Socket, %{})
      after
        # Restore original environment
        Application.put_env(:mix, :env, original_env)
      end
    end
  end
  
  describe "id/1" do
    test "returns user socket id" do
      # Create a test user
      user = create_test_user()
      
      # Generate a token
      token = create_test_token(user)
      
      # Connect with the token
      {:ok, socket} = connect(Socket, %{"token" => token})
      
      # Check the socket id
      assert Socket.id(socket) == "user_socket:#{user.id}"
    end
  end
end