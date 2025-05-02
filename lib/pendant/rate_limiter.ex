defmodule Pendant.RateLimiter do
  @moduledoc """
  Rate limiter for API and socket operations.
  
  Implements a token bucket algorithm for rate limiting in emergency
  communication scenarios where bandwidth is precious.
  """
  
  use GenServer
  require Logger
  
  # Default bucket configuration
  @default_bucket %{
    # Maximum number of tokens
    max_tokens: 20,
    # Initial tokens
    tokens: 20,
    # Tokens per second refill rate
    refill_rate: 2,
    # Last refill timestamp
    last_refill: 0
  }
  
  # API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Check if an operation should be rate limited.
  
  Returns {:ok, remaining_tokens} if allowed, or {:error, :rate_limited} if denied.
  """
  def check_rate_limit(client_id, operation, cost \\ 1) do
    GenServer.call(__MODULE__, {:check, client_id, operation, cost})
  end
  
  @doc """
  Get the current bucket state for a client.
  """
  def get_bucket(client_id, operation) do
    GenServer.call(__MODULE__, {:get_bucket, client_id, operation})
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    # Initialize state with empty bucket map
    {:ok, %{buckets: %{}}}
  end
  
  @impl true
  def handle_call({:check, client_id, operation, cost}, _from, state) do
    # Get current time for token refill calculation
    now = System.system_time(:millisecond)
    
    # Generate bucket key
    bucket_key = "#{client_id}:#{operation}"
    
    # Get or create bucket
    bucket = Map.get(
      state.buckets, 
      bucket_key, 
      Map.put(@default_bucket, :last_refill, now)
    )
    
    # Apply refill based on time elapsed
    bucket = refill_tokens(bucket, now)
    
    # Check if enough tokens are available
    if bucket.tokens >= cost do
      # Consume tokens
      new_bucket = %{bucket | tokens: bucket.tokens - cost}
      
      # Update state
      new_state = %{state | buckets: Map.put(state.buckets, bucket_key, new_bucket)}
      
      {:reply, {:ok, new_bucket.tokens}, new_state}
    else
      # Rate limited - don't update the bucket state
      Logger.warning("Rate limit exceeded for #{client_id} on #{operation}")
      {:reply, {:error, :rate_limited}, state}
    end
  end
  
  @impl true
  def handle_call({:get_bucket, client_id, operation}, _from, state) do
    # Generate bucket key
    bucket_key = "#{client_id}:#{operation}"
    
    # Get current time
    now = System.system_time(:millisecond)
    
    # Get bucket or create default
    bucket = Map.get(
      state.buckets, 
      bucket_key, 
      Map.put(@default_bucket, :last_refill, now)
    )
    
    # Apply refill based on time elapsed
    bucket = refill_tokens(bucket, now)
    
    {:reply, bucket, state}
  end
  
  # Helper functions
  
  # Refill tokens based on elapsed time
  defp refill_tokens(bucket, now) do
    # Calculate time elapsed since last refill in milliseconds
    elapsed_ms = now - bucket.last_refill
    
    # Convert to seconds (can be fractional)
    elapsed_seconds = elapsed_ms / 1000
    
    # Calculate tokens to add
    tokens_to_add = elapsed_seconds * bucket.refill_rate
    
    if tokens_to_add > 0 do
      # Add tokens (capped at max_tokens)
      new_tokens = min(bucket.max_tokens, bucket.tokens + tokens_to_add)
      
      # Update bucket
      %{bucket | tokens: new_tokens, last_refill: now}
    else
      # No change needed
      bucket
    end
  end
end