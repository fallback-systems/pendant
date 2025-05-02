defmodule Pendant.Chat.CRDTSupervisor do
  @moduledoc """
  Supervisor for CRDT manager processes.
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Registry for CRDT manager processes
      {Registry, keys: :unique, name: Pendant.CRDTRegistry},
      
      # Dynamic supervisor for CRDT manager processes
      {DynamicSupervisor, strategy: :one_for_one, name: Pendant.CRDTSupervisor}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end