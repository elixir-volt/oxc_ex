defmodule OxcExTest do
  use ExUnit.Case
  doctest OxcEx

  test "greets the world" do
    assert OxcEx.hello() == :world
  end
end
