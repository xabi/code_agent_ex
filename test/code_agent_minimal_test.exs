defmodule CodeAgentMinimalTest do
  use ExUnit.Case
  doctest CodeAgentMinimal

  test "greets the world" do
    assert CodeAgentMinimal.hello() == :world
  end
end
