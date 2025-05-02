defmodule Pendant.Web.Layouts do
  @moduledoc false
  use Phoenix.Component
  import Phoenix.Controller
  
  # Define the paths and csrf token needed in the templates
  
  # The path helpers
  def sigil_p(path, _opts) do
    path = path
    |> String.trim_leading("/")
    |> String.replace_prefix("/", "")
    
    "/#{path}"
  end
  
  # The default app layout for HTML pages
  embed_templates "layouts/*"
end