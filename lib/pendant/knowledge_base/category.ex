defmodule Pendant.KnowledgeBase.Category do
  @moduledoc """
  Schema for knowledge base categories.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Pendant.KnowledgeBase.Article

  schema "categories" do
    field :name, :string
    field :description, :string
    field :icon, :string
    
    has_many :articles, Article

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :icon])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end