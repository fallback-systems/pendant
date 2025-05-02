defmodule Pendant.Web.DashboardLive do
  @moduledoc """
  LiveView for the dashboard page.
  """
  use Phoenix.LiveView
  alias Pendant.KnowledgeBase.Search
  alias Pendant.Meshtastic.Handler, as: MeshtasticHandler
  alias Pendant.WiFi.AccessPoint
  
  @update_interval 10_000  # 10 seconds
  
  @impl true
  def mount(_params, _session, socket) do
    # Start periodic timer for updates
    if connected?(socket) do
      :timer.send_interval(@update_interval, self(), :update_status)
    end
    
    # Get initial data
    {:ok, important_articles} = Search.important_articles(5)
    {:ok, categories} = Search.list_categories()
    
    socket = socket
      |> assign(:page_title, "Emergency Dashboard")
      |> assign(:important_articles, important_articles)
      |> assign(:categories, categories)
      |> assign(:meshtastic_status, get_meshtastic_status())
      |> assign(:wifi_status, get_wifi_status())
      |> assign(:system_status, get_system_status())
    
    {:ok, socket}
  end
  
  @impl true
  def handle_info(:update_status, socket) do
    socket = socket
      |> assign(:meshtastic_status, get_meshtastic_status())
      |> assign(:wifi_status, get_wifi_status())
      |> assign(:system_status, get_system_status())
      
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_redirect(socket, to: "/search?q=#{URI.encode(query)}")}
  end
  
  defp get_meshtastic_status do
    MeshtasticHandler.status()
  end
  
  defp get_wifi_status do
    %{
      ap: AccessPoint.status(),
      clients: AccessPoint.connected_clients(),
    }
  end
  
  defp get_system_status do
    %{
      uptime: get_uptime(),
      memory_usage: get_memory_usage(),
      disk_usage: get_disk_usage(),
      articles_count: Search.count_entries()
    }
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
  
  defp get_memory_usage do
    memory = :erlang.memory()
    used = memory[:total]
    total = 512 * 1024 * 1024  # Assume 512MB
    percent = Float.round(used / total * 100, 1)
    
    "#{format_bytes(used)} / #{format_bytes(total)} (#{percent}%)"
  end
  
  defp get_disk_usage do
    # Placeholder for actual implementation
    %{used: "123MB", total: "8GB", percent: 15}
  end
  
  defp format_bytes(bytes) when bytes < 1024 do
    "#{bytes} B"
  end
  
  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    kb = Float.round(bytes / 1024, 2)
    "#{kb} KB"
  end
  
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024 do
    mb = Float.round(bytes / (1024 * 1024), 2)
    "#{mb} MB"
  end
  
  defp format_bytes(bytes) do
    gb = Float.round(bytes / (1024 * 1024 * 1024), 2)
    "#{gb} GB"
  end
end