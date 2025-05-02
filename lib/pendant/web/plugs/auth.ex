defmodule Pendant.Web.Plugs.Auth do
  @moduledoc """
  Authentication plug for requests.
  """
  import Plug.Conn
  alias Pendant.Auth
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user_data} <- Auth.verify_token(token) do
      conn
      |> assign(:user_id, user_data.user_id)
      |> assign(:roles, user_data.roles)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end