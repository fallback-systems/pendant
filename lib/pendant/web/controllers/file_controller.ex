defmodule Pendant.Web.FileController do
  use Phoenix.Controller
  
  @uploads_path "/home/user/dev/pendant/priv/static/uploads"
  
  def show(conn, %{"path" => path}) do
    # For security, ensure path doesn't have any traversal attempts
    sanitized_path = Path.basename(path)
    file_path = Path.join(@uploads_path, sanitized_path)
    
    case File.read(file_path) do
      {:ok, content} ->
        # Determine content type
        content_type = MIME.from_path(file_path) || "application/octet-stream"
        
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, content)
        
      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> text("File not found")
    end
  end
end