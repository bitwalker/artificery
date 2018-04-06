defmodule Artificery.Option do
  @moduledoc false

  defstruct name: nil,
    type: :string,
    help: nil,
    flags: %{}

  # These mimic those accepted by OptionParser
  @type option_type :: :boolean
                     | :integer
                     | :float
                     | :string
                     | :count
                     | :keep

  @type t :: %__MODULE__{
    name: atom,
    type: option_type,
    help: nil | String.t,
    flags: map
  }

  @valid_flags [
    :required,
    :default,
    :alias,
    :transform,
    :hidden,
    :accumulate
  ]

  @doc """
  Creates a new Option struct
  """
  @spec new(atom, map) :: t
  def new(name, flags) when is_atom(name) and is_map(flags) do
    type = Map.get(flags, :type) || :string
    help = Map.get(flags, :help)
    {_, flags} = Map.split(flags, [:type, :help])
    %__MODULE__{
      name: name,
      type: type,
      help: help,
      flags: flags
    }
  end

  @doc """
  Validates the Option struct, raising an error if invalid
  """
  @spec validate!(t, [caller: module]) :: :ok | no_return
  def validate!(%__MODULE__{flags: flags}, caller: caller) do
    validate_flags!(caller, flags)
  end

  defp validate_flags!(caller, flags) when is_map(flags) do
    do_validate_flags!(caller, Map.to_list(flags))
  end
  defp do_validate_flags!(_caller, []), do: :ok
  defp do_validate_flags!(caller, [{:transform, transform} | rest]) do
    case transform do
      nil ->
        :ok
      f when is_function(f, 1) ->
        :ok
      a when is_atom(a) ->
        :ok
      {m, f, a} when is_atom(m) and is_atom(f) and is_list(a) ->
        arity = length(a) + 1
        if function_exported?(m, f, arity) do
          :ok
        else
          raise "Invalid transform: #{m}.#{f}/#{arity} is either undefined or not exported!"
        end
    end
    do_validate_flags!(caller, rest)
  end
  defp do_validate_flags!(caller, [{bool_flag, v} | rest]) when bool_flag in [:required, :hidden] do
    if is_boolean(v) do
      :ok
    else
      raise "Invalid value for '#{inspect bool_flag}' - should be true or false, got: #{inspect v}"
    end
    do_validate_flags!(caller, rest)
  end
  defp do_validate_flags!(caller, [{flag, _} | rest]) when is_atom(flag) do
    if flag in @valid_flags do
      :ok
    else
      invalid_flag = Atom.to_string(flag)
      closest =
        @valid_flags
        |> Enum.map(&Atom.to_string/1)
        |> Enum.max_by(fn f -> String.jaro_distance(invalid_flag, f) end)
      raise "Invalid option flag '#{invalid_flag}', did you mean '#{closest}'?"
    end
    do_validate_flags!(caller, rest)
  end
end
