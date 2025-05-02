defmodule Pendant.Web.StatusController do
  @moduledoc """
  Controller for system status API endpoints.
  """
  use Phoenix.Controller
  
  alias Pendant.Meshtastic.Handler, as: MeshtasticHandler
  alias Pendant.WiFi.AccessPoint
  alias Pendant.P2P.Manager, as: P2PManager
  
  def index(conn, _params) do
    # Collect status information from various components
    status = %{
      device: %{
        name: "Pendant Emergency Device",
        version: Application.spec(:pendant, :vsn),
        uptime: get_uptime()
      },
      meshtastic: MeshtasticHandler.status(),
      wifi: %{
        ap: AccessPoint.status(),
        client_count: length(AccessPoint.connected_clients())
      },
      p2p: P2PManager.status()
    }
    
    # Return as JSON
    json(conn, status)
  end
  
  defp get_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime, 1000)
    
    days = div(seconds, 86400)
    seconds = rem(seconds, 86400)
    hours = div(seconds, 3600)
    seconds = rem(seconds, 3600)
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)
    
    "#{days}d #{hours}h #{minutes}m #{seconds}s"
  end
end