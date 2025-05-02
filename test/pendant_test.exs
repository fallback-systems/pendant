defmodule PendantTest do
  use ExUnit.Case
  doctest Pendant

  test "greets the world" do
    assert Pendant.hello() == :world
  end
end
