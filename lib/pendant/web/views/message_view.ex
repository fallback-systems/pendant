defmodule Pendant.Web.MessageView do
  use Phoenix.View, root: "lib/pendant/web/templates"
  
  def render("message.json", %{message: message}) do
    %{
      id: message.id,
      content: message.content,
      message_type: message.message_type,
      inserted_at: message.inserted_at,
      user: %{
        id: message.user.id,
        username: message.user.username,
        display_name: message.user.display_name,
        avatar: message.user.avatar
      },
      room_id: message.room_id
    }
    |> add_file_data(message)
  end
  
  defp add_file_data(json, %{message_type: "file"} = message) do
    Map.merge(json, %{
      file_path: message.file_path,
      file_name: message.file_name,
      file_size: message.file_size,
      file_type: message.file_type
    })
  end
  
  defp add_file_data(json, _), do: json
end