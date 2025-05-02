defmodule Pendant.Web.UserRoomView do
  use Phoenix.View, root: "lib/pendant/web/templates"
  
  def render("user_room.json", %{user_room: %{user: user, role: role, last_read_at: last_read_at}}) do
    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar: user.avatar,
      status: user.status,
      role: role,
      last_read_at: last_read_at
    }
  end
end