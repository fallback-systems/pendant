defmodule Pendant.SimpleTest do
  use ExUnit.Case
  
  test "basic assertions" do
    # Basic assertions
    assert true
    refute false
    assert 1 + 1 == 2
    assert "hello" <> " " <> "world" == "hello world"
    
    # Map assertions
    map = %{a: 1, b: 2}
    assert map.a == 1
    assert Map.get(map, :b) == 2
    
    # List assertions
    list = [1, 2, 3]
    assert length(list) == 3
    assert Enum.at(list, 0) == 1
    
    # Error handling
    assert_raise ArithmeticError, fn -> 1 / 0 end
  end
end