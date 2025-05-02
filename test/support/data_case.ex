defmodule Pendant.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Pendant.KnowledgeBase.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Pendant.TestHelpers
      import Pendant.DataCase
    end
  end

  setup tags do
    Ecto.Adapters.SQL.Sandbox.checkout(Pendant.KnowledgeBase.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Pendant.KnowledgeBase.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  Helper to create changeset errors for non-valid data.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end