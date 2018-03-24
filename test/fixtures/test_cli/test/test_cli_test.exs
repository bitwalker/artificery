defmodule TestCliTest do
  use ExUnit.Case
  doctest TestCli

  test "greets the world" do
    assert TestCli.hello() == :world
  end
end
