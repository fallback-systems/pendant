defmodule Pendant.Web.Endpoint do
  @moduledoc """
  Phoenix endpoint for the pendant web interface.
  """
  use Phoenix.Endpoint, otp_app: :pendant

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  @session_options [
    store: :cookie,
    key: "_pendant_key",
    signing_salt: "Gjw8fDDl"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
  
  # Socket for chat functionality
  socket "/socket", Pendant.Web.Socket,
    websocket: true,
    longpoll: false

  # Serve static assets from the app's priv/static folder
  plug Plug.Static,
    at: "/",
    from: :pendant,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Pendant.Web.Router
end