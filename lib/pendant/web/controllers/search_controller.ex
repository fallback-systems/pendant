defmodule Pendant.Web.SearchController do
  @moduledoc """
  Controller for knowledge base search API endpoints.
  """
  use Phoenix.Controller
  
  alias Pendant.KnowledgeBase.Search
  
  def search(conn, %{"q" => query}) do
    # Search the knowledge base
    case Search.find(query) do
      {:ok, results} ->
        json(conn, %{
          query: query,
          count: length(results),
          results: results
        })
        
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Search failed", reason: reason})
    end
  end
  
  def search(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing query parameter 'q'"})
  end
end