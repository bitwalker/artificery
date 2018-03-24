defmodule Artificery.Test.CLI do
  use Artificery

  option :verbose, :boolean, "Turns on verbose logging"

  command :hello, "Says hello" do
    argument :name, :string, "Name of person to greet"
  end

  def hello(_args, %{name: name}) do
    Artificery.Console.notice "Hello #{name}!"
  end
end
