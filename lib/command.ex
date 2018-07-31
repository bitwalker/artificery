defmodule Artificery.Command do
  @moduledoc false

  @behaviour Access

  defstruct name: nil,
    callback: nil,
    # Options are keyed, so use a map for easy access
    options: %{},
    # This is a list since they are positional, order matters
    arguments: [],
    # Subcommands are also keyed
    subcommands: %{},
    help: nil,
    hidden: false

  @type t :: %__MODULE__{
    callback: atom,
    options: %{atom => Artificery.Option.t},
    arguments: [Artificery.Option.t],
    subcommands: %{atom => t},
    help: nil | String.t,
    hidden: boolean
  }

  @doc """
  Creates a new Command struct, with the given flags applied
  """
  @spec new(atom, map) :: t
  def new(name, flags) when is_map(flags) do
    callback =
      case Map.get(flags, :callback) do
        nil ->
          name
        a when is_atom(a) ->
          a
      end
    %__MODULE__{
      name: name,
      help: Map.get(flags, :help),
      hidden: Map.get(flags, :hidden, false),
      callback: callback
    }
  end

  @doc """
  Extends the given Command with a new option
  """
  @spec add_option(t, Artificery.Option.t) :: t
  def add_option(%__MODULE__{options: opts} = c, %Artificery.Option{name: name} = opt) do
    %{c | options: Map.put(opts, name, opt)}
  end

  @doc """
  Extends the given Command with a new positional argument
  """
  @spec add_argument(t, Artificery.Option.t) :: t
  def add_argument(%__MODULE__{arguments: args} = c, %Artificery.Option{} = arg) do
    %{c | arguments: args ++ [arg]}
  end

  @doc false
  @impl Access
  def fetch(%__MODULE__{} = c, key) do
    case Map.get(c, key) do
      nil ->
        :error
      val ->
        {:ok, val}
    end
  end

  @doc false
  def get(%__MODULE__{} = c, key, default \\ nil) do
    case Map.get(c, key) do
      nil ->
        default
      val ->
        val
    end
  end

  @doc false
  @impl Access
  def get_and_update(c, key, fun) do
    {get_data, kv} =
      c
      |> Map.from_struct
      |> Access.get_and_update(key, fun)
    {get_data, struct(__MODULE__, kv)}
  end

  @doc false
  @impl Access
  def pop(c, key) do
    {val, kv} =
      c
      |> Map.from_struct
      |> Map.pop(key)
    {val, struct(__MODULE__, kv)}
  end
end
