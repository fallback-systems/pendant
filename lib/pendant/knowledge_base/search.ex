defmodule Pendant.KnowledgeBase.Search do
  @moduledoc """
  Provides search functionality for the knowledge base.
  """
  import Ecto.Query
  alias Pendant.KnowledgeBase.{Repo, Article, Category}

  @doc """
  Search for articles by query string.
  
  Searches in title, content, and tags.
  """
  def find(query) do
    query_terms = prepare_query(query)
    
    query = from a in Article,
      left_join: c in Category, on: a.category_id == c.id,
      where: fragment("? MATCH ?", a.title, ^query_terms) or
             fragment("? MATCH ?", a.content, ^query_terms) or
             fragment("? MATCH ?", a.tags, ^query_terms),
      order_by: [desc: a.importance, desc: a.updated_at],
      select: %{
        id: a.id,
        title: a.title,
        summary: a.summary,
        category: c.name,
        importance: a.importance,
        updated_at: a.updated_at
      }
      
    {:ok, Repo.all(query)}
  rescue
    error ->
      {:error, "Search error: #{inspect(error)}"}
  end
  
  @doc """
  Get an article by ID with its category.
  """
  def get_article(id) do
    query = from a in Article,
      left_join: c in Category, on: a.category_id == c.id,
      where: a.id == ^id,
      select: %{
        id: a.id,
        title: a.title,
        content: a.content,
        summary: a.summary,
        category: c.name,
        category_id: c.id,
        importance: a.importance,
        tags: a.tags,
        updated_at: a.updated_at
      }
      
    case Repo.one(query) do
      nil -> {:error, "Article not found"}
      article -> {:ok, article}
    end
  end
  
  @doc """
  List all articles in a category.
  """
  def list_by_category(category_id) do
    query = from a in Article,
      where: a.category_id == ^category_id,
      order_by: [desc: a.importance, asc: a.title],
      select: %{
        id: a.id,
        title: a.title,
        summary: a.summary,
        importance: a.importance,
        updated_at: a.updated_at
      }
      
    {:ok, Repo.all(query)}
  end
  
  @doc """
  List all categories.
  """
  def list_categories do
    query = from c in Category,
      order_by: c.name,
      select: %{
        id: c.id,
        name: c.name,
        description: c.description,
        icon: c.icon
      }
      
    {:ok, Repo.all(query)}
  end
  
  @doc """
  Get most important articles across all categories.
  """
  def important_articles(limit \\ 10) do
    query = from a in Article,
      left_join: c in Category, on: a.category_id == c.id,
      order_by: [desc: a.importance, desc: a.updated_at],
      limit: ^limit,
      select: %{
        id: a.id,
        title: a.title,
        summary: a.summary,
        category: c.name,
        importance: a.importance
      }
      
    {:ok, Repo.all(query)}
  end
  
  @doc """
  Count the total number of articles in the knowledge base.
  """
  def count_entries do
    Repo.aggregate(Article, :count, :id)
  end
  
  # Private functions
  
  defp prepare_query(query) do
    # Prepare query for SQLite FTS search
    query
    |> String.split()
    |> Enum.map(&"#{&1}*")
    |> Enum.join(" OR ")
  end
end