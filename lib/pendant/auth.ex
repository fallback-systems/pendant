defmodule Pendant.Auth do
  @moduledoc """
  Authentication and authorization functionality for Pendant.
  
  Provides secure token generation, verification, and role-based access control
  to protect system resources during emergency scenarios.
  """
  
  require Logger
  alias Pendant.Chat.{User, UserRoom}
  alias Pendant.KnowledgeBase.Repo
  import Ecto.Query
  
  # Token validity period (24 hours by default, can be configured)
  @token_validity_seconds Application.compile_env(:pendant, :token_validity_seconds, 86400)
  
  # Signing salt (should be loaded from environment in production)
  @signing_salt Application.compile_env(:pendant, :signing_salt, "pendant_secure_salt")
  
  @doc """
  Generate a secure authentication token for a user.
  
  Returns a JWT token containing the user ID and roles.
  """
  def generate_token(user_id) do
    # Get user roles if the user exists
    roles = get_user_roles(user_id)
    
    # Generate a token with user_id, roles and metadata
    Phoenix.Token.sign(
      Pendant.Web.Endpoint,
      @signing_salt,
      %{
        user_id: user_id,
        roles: roles,
        created_at: DateTime.utc_now() |> DateTime.to_unix()
      }
    )
  end
  
  @doc """
  Verify a token and extract the user data.
  
  Returns {:ok, user_data} if the token is valid, or {:error, reason} otherwise.
  """
  def verify_token(token) do
    case Phoenix.Token.verify(Pendant.Web.Endpoint, @signing_salt, token, max_age: @token_validity_seconds) do
      {:ok, user_data} ->
        # Verify the user still exists
        case Repo.get(User, user_data.user_id) do
          nil -> 
            Logger.warning("Token verification failed: user not found")
            {:error, :user_not_found}
          _user -> 
            # Update the roles in case they've changed
            updated_data = Map.put(user_data, :roles, get_user_roles(user_data.user_id))
            {:ok, updated_data}
        end
        
      {:error, reason} ->
        Logger.warning("Token verification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Check if a user has permission to access a room.
  
  Returns true if the user is authorized, false otherwise.
  """
  def can_access_room?(user_id, room_id) do
    # Admin role has access to all rooms
    if has_role?(user_id, "admin") do
      true
    else
      # Check if user is a member of the room
      query = from ur in UserRoom,
              where: ur.user_id == ^user_id and ur.room_id == ^room_id,
              select: ur.id
              
      Repo.exists?(query)
    end
  end
  
  @doc """
  Check if a user has permission to modify a room's CRDT.
  
  Returns true if the user is authorized, false otherwise.
  """
  def can_modify_crdt?(user_id, room_id) do
    # Only room members can modify CRDT data
    can_access_room?(user_id, room_id)
  end
  
  @doc """
  Check if a user has a specific role.
  
  Returns true if the user has the role, false otherwise.
  """
  def has_role?(user_id, role) do
    roles = get_user_roles(user_id)
    Enum.member?(roles, role)
  end
  
  @doc """
  Get the roles for a user.
  
  Returns a list of role strings.
  """
  def get_user_roles(user_id) do
    # Check if user exists
    case Repo.get(User, user_id) do
      nil -> []
      user ->
        # Get user's roles from their room memberships
        query = from ur in UserRoom,
                where: ur.user_id == ^user_id,
                select: ur.role
                
        roles = Repo.all(query)
        
        # Add default role
        ["user" | roles]
    end
  end
  
  @doc """
  Create a demo user for development/testing.
  Not recommended for production use.
  """
  def create_demo_user(username) do
    # Only for development/testing!
    if Mix.env() == :prod do
      {:error, :not_allowed_in_production}
    else
      case Repo.get_by(User, username: username) do
        nil ->
          # Create new user
          {:ok, user} = Pendant.Chat.create_user(%{
            username: username,
            display_name: "Demo User: #{username}",
            device_id: "demo_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
            status: "online"
          })
          
          user
          
        user ->
          # Return existing user
          user
      end
    end
  end
end