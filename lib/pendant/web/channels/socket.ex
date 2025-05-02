defmodule Pendant.Web.Socket do
  use Phoenix.Socket

  ## Channels
  channel "chat:*", Pendant.Web.ChatChannel
  channel "crdt:*", Pendant.Web.ChatChannel

  @impl true
  def connect(params, socket, _connect_info) do
    {:ok, assign(socket, :user_id, params["user_id"] || :rand.uniform(1000))}
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end