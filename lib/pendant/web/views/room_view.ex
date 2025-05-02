defmodule Pendant.Web.RoomView do
  use Phoenix.View, root: "lib/pendant/web/templates"
  
  def render("room.json", %{room: room}) do
    %{
      id: room.id,
      name: room.name,
      description: room.description,
      room_type: room.room_type,
      crdt_enabled: room.crdt_enabled,
      crdt_type: room.crdt_type,
      inserted_at: room.inserted_at
    }
  end
  
  def render("room_with_messages.json", %{room: room, messages: messages, users: users}) do
    %{
      id: room.id,
      name: room.name,
      description: room.description,
      room_type: room.room_type,
      crdt_enabled: room.crdt_enabled,
      crdt_type: room.crdt_type,
      inserted_at: room.inserted_at,
      messages: messages,
      users: users
    }
  end
end