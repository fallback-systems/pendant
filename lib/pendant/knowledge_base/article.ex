defmodule Pendant.KnowledgeBase.Article do
  @moduledoc """
  Schema for knowledge base articles.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Pendant.KnowledgeBase.Category

  schema "articles" do
    field :title, :string
    field :content, :string
    field :summary, :string
    field :importance, :integer, default: 1
    field :tags, :string
    
    belongs_to :category, Category

    timestamps()
  end

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :content, :summary, :category_id, :importance, :tags])
    |> validate_required([:title, :content])
    |> foreign_key_constraint(:category_id)
  end
  
  @doc """
  Parse tags string into a list of tags
  """
  def parse_tags(nil), do: []
  def parse_tags(tags_string) do
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn tag -> tag != "" end)
  end
  
  @doc """
  Format a list of tags into a tags string
  """
  def format_tags(tags) when is_list(tags) do
    Enum.join(tags, ", ")
  end
end