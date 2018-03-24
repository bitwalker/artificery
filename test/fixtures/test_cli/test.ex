defmodule A do
  defmacro foo(x, y) when is_integer(x) when is_integer(y) do
    quote do
      unquote(x) + unquote(y)
    end
  end
end
