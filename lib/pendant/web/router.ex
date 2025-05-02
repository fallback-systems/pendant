defmodule Pendant.Web.Router do
  @moduledoc """
  Phoenix router for the pendant web interface.
  """
  use Phoenix.Router
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {Pendant.Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Pendant.Web do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/categories", CategoryLive.Index, :index
    live "/categories/:id", CategoryLive.Show, :show
    live "/articles", ArticleLive.Index, :index
    live "/articles/:id", ArticleLive.Show, :show
    live "/search", SearchLive, :index
    
    # System status and control
    live "/system", SystemLive, :index
    live "/network", NetworkLive, :index
    live "/meshtastic", MeshtasticLive, :index
    
    # Chat interface
    live "/chat", ChatLive, :index
    live "/chat/:room_id", ChatLive, :show
  end

  # API routes for mobile apps or other pendant devices
  scope "/api", Pendant.Web do
    pipe_through :api

    get "/status", StatusController, :index
    get "/categories", CategoryController, :index
    get "/categories/:id", CategoryController, :show
    get "/articles", ArticleController, :index
    get "/articles/:id", ArticleController, :show
    get "/search", SearchController, :search
    
    # Meshtastic messaging API
    post "/messages", MessageController, :send
    get "/messages/history", MessageController, :history
    get "/messages/status", MessageController, :status
    
    # Chat API endpoints
    post "/chat/users", ChatController, :create_user
    get "/chat/rooms", ChatController, :list_rooms
    get "/chat/rooms/:id", ChatController, :get_room
    post "/chat/rooms", ChatController, :create_room
    post "/chat/rooms/:room_id/join", ChatController, :join_room
    get "/chat/rooms/:room_id/messages", ChatController, :get_messages
    post "/chat/rooms/:room_id/messages", ChatController, :send_message
    get "/chat/rooms/:room_id/users", ChatController, :get_room_users
    get "/chat/rooms/:room_id/crdt", ChatController, :get_crdt
    post "/chat/rooms/:room_id/crdt", ChatController, :update_crdt
  end
end