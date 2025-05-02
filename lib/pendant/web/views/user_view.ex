defmodule Pendant.Web.UserView do
  use Phoenix.View, root: "lib/pendant/web/templates"
  
  def render("user.json", %{user: user}) do
    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar: user.avatar,
      status: user.status,
      last_seen_at: user.last_seen_at
    }
  end
end