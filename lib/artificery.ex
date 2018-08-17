defmodule Artificery do
  @moduledoc """
  This module defines the behaviour and public API for Artificery command line applications.

  ## Usage

  To get started, simply `use` this module, and you can start defining your CLI right away:

      use Artificery

      command :hello, "Say hello" do
        option :name, :string, "The name of the person to greet"
      end

      ...

      def hello(_argv, %{name: name}) do
        Console.success "Hello \#{name}!"
      end

  This module exports a few macros for building up complex CLI applications, so please review
  the documentation for more information on each, and how to use them.
  """
  alias __MODULE__.Command

  @type argv :: [String.t]
  @type options :: %{atom => term}

  @callback pre_dispatch(Command.t, argv, options) :: {:ok, options} | no_return

  @doc false
  defmacro __using__(opts) when is_list(opts) do
    quote location: :keep do
      require unquote(__MODULE__).Entry

      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__).Entry

      alias Artificery.Console
      require Artificery.Console

      Module.register_attribute(__MODULE__, :commands, persist: true)
      Module.register_attribute(__MODULE__, :options, persist: true)
      Module.register_attribute(__MODULE__, :global_options, persist: true)

      Module.put_attribute(__MODULE__, :commands, %{})
      Module.put_attribute(__MODULE__, :options, %{})
      Module.put_attribute(__MODULE__, :global_options, %{})

      import unquote(__MODULE__),
        only: [command: 2, command: 3, command: 4,
               # define options for reuse
               defoption: 3, defoption: 4,
               # option/1 and /2 are used to import opts defined via defoption
               option: 1, option: 2,
               # option/3 and /4 are inline option definitions
               option: 3, option: 4,
               # arguments are effectively positional options
               argument: 2, argument: 3, argument: 4]

      var!(current_command, unquote(__MODULE__)) = nil

      @doc false
      @impl unquote(__MODULE__)
      def pre_dispatch(_cmd, _argv, opts), do: {:ok, opts}

      defoverridable pre_dispatch: 3
    end
  end


  @doc """
  Defines a new command with the given name and either help text or flags

  ## Example

      command :info, "Displays info about stuff"

      command :info, hidden: true
  """
  defmacro command(name, help) when is_atom(name) and is_binary(help) do
    quote location: :keep do
      command(unquote(name), [], unquote(help), do: nil)
    end
  end
  defmacro command(name, flags) when is_atom(name) and is_list(flags) do
    quote location: :keep do
      command(unquote(name), unquote(flags), nil, do: nil)
    end
  end

  @doc """
  Defines a new command with the given name, flags or help text, and definition,
  or flags, help text, and no definition

  ## Example

      command :info, "Displays info about stuff" do
        ...
      end

      command :info, [hidden: true] do
        ...
      end

      command :info, [hidden: true], "Displays info about stuff" do
        ...
      end
  """
  defmacro command(name, help, do: block) when is_atom(name) and is_binary(help) do
    quote location: :keep do
      command(unquote(name), [], unquote(help), do: unquote(block))
    end
  end
  defmacro command(name, flags, do: block) when is_atom(name) and is_list(flags) do
    quote location: :keep do
      command(unquote(name), unquote(flags), nil, do: unquote(block))
    end
  end
  defmacro command(name, flags, help) when is_atom(name) and is_list(flags) and is_binary(help) do
    quote location: :keep do
      command(unquote(name), unquote(flags), unquote(help), do: nil)
    end
  end

  @doc """
  Defines a new command with the given name, flags, help text, and definition

  ## Example

      command :admin, hidden: true, "Does admin stuff" do
        ...
      end
  """
  defmacro command(name, flags, help, do: block)
           when is_atom(name) and is_list(flags) and (is_nil(help) or is_binary(help)) do
    empty_block? = is_nil(block)

    quote location: :keep do
      commands = Module.get_attribute(__MODULE__, :commands)
      current_command = var!(current_command, unquote(__MODULE__))

      command_name = unquote(name)
      command_flags = Map.new(unquote(flags))

      command_flags =
        case command_flags[:callback] do
          nil ->
            Map.put(command_flags, :callback, command_name)

          _cb ->
            command_flags
        end

      command_flags =
        case unquote(help) do
          "" ->
            command_flags

          help ->
            Map.put(command_flags, :help, help)
        end

      new_cmd = Artificery.Command.new(command_name, command_flags)

      new_current_command =
        case current_command do
          nil ->
            # Top level command
            Module.put_attribute(__MODULE__, :commands, Map.put(commands, command_name, new_cmd))

            if unquote(empty_block?) do
              nil
            else
              var!(current_command, unquote(__MODULE__)) = command_name
              unquote(block)
              nil
            end

          a when is_atom(a) ->
            # Subcommand
            current_cmd = get_in(commands, [current_command])

            current_cmd =
              Map.put(
                current_cmd,
                :subcommands,
                Map.put(current_cmd.subcommands, command_name, new_cmd)
              )

            Module.put_attribute(__MODULE__, :commands, Map.put(commands, current_command, current_cmd))

            if unquote(empty_block?) do
              current_command
            else
              var!(current_command, unquote(__MODULE__)) = [current_command, command_name]
              unquote(block)
              current_command
            end

          path when is_list(path) ->
            # Nested subcommand
            access_path = Enum.intersperse(path, :subcommands)
            current_cmd = get_in(commands, access_path)

            commands =
              put_in(
                commands,
                access_path ++ [:subcommands],
                Map.put(current_cmd.subcommands, command_name, new_cmd)
              )

            Module.put_attribute(__MODULE__, :commands, commands)

            if unquote(empty_block?) do
              current_command
            else
              var!(current_command, unquote(__MODULE__)) = path ++ [command_name]
              unquote(block)
              current_command
            end
        end

      var!(current_command, unquote(__MODULE__)) = new_current_command
    end
  end

  @doc """
  Defines an option which can be imported into one or more commands. This is an abstract
  option definition, i.e. it doesn't define an option in any scope, it defines options for reuse.

  This macro takes the option name, type, and either help text or options

  Valid types are the same as those defined in `OptionParser`

  ## Example

      defoption :verbose, :boolean, "Turns on verbose output"

      defoption :verbose, :boolean, hidden: true
  """
  defmacro defoption(name, type, flags) when is_atom(name) and is_atom(type) and is_list(flags) do
    quote location: :keep do
      defoption(unquote(name), unquote(type), nil, unquote(flags))
    end
  end
  defmacro defoption(name, type, help) when is_atom(name) and is_atom(type) do
    quote location: :keep do
      defoption(unquote(name), unquote(type), unquote(help), [])
    end
  end

  @doc """
  Like `defoption/3`, but takes the option name, type, help, and flags

  ## Example

      defoption :verbose, :boolean, "Turns on verbose output", hidden: true
  """
  defmacro defoption(name, type, help, flags) when is_atom(name) and is_atom(type) and is_list(flags) do
    quote location: :keep do
      options = Module.get_attribute(__MODULE__, :options)

      option_name = unquote(name)
      option_flags =
        Map.new(unquote(flags))
        |> Map.put(:help, unquote(help))
        |> Map.put(:type, unquote(type))
      opt = Artificery.Option.new(option_name, option_flags)
      Artificery.Option.validate!(opt, caller: __MODULE__)

      unless Map.get(options, option_name) == nil do
        raise "Cannot define two options with the same name! Duplicate of '#{option_name}' found"
      end

      Module.put_attribute(__MODULE__, :options, Map.put(options, option_name, opt))
    end
  end

  @doc """
  Imports an option defined via `defoption` into the current scope.

  You may optionally override flags for a given option by passing a keyword list as a second argument.
  You are not allowed to override the type of the option, but you may override the help text, by passing
  `help: "..."` as an override. If you need to override the type, it is better if you use `option/3` or `option/4`

  ## Example

      defoption :name, :string, "Name of person"

      command :hello, "Says hello" do
        # Import with no overrides
        option :name

        # Import with overrides
        option :name, required: true, alias: :n

        # Import and customize help text
        option :name, help: "Name of the person to greet"
      end
  """
  defmacro option(name) when is_atom(name) do
    quote location: :keep do
      option(unquote(name), [])
    end
  end

  @doc """
  When used in the following form:

      option :foo, :string

  This defines a new option, foo, of type string, with no help or flags defined

  When used like this:

      option :foo, required: true

  It imports an option definition (as created via `defoption`) and provides overrides
  for the original definition.
  """
  defmacro option(name, overrides) when is_atom(name) and is_list(overrides) do
    quote location: :keep do
      current_command = var!(current_command, unquote(__MODULE__))
      commands = Module.get_attribute(__MODULE__, :commands)
      options = Module.get_attribute(__MODULE__, :options)
      global_options = Module.get_attribute(__MODULE__, :global_options)

      option_name = unquote(name)
      opt = Map.get(options, option_name)

      if opt == nil do
        raise "No such option '#{option_name}' has been defined yet"
      end

      # Apply overridden flags
      overrides = unquote(overrides)
      # Allow overriding help text
      help = Keyword.get(overrides, :help, opt.help)
      {_disallowed, overrides} = Keyword.split(unquote(overrides), [:type, :help, :flags])
      # Build up new flags based on overrides
      new_flags = Map.merge(opt.flags, Map.new(overrides))
      # Update option
      opt = %Artificery.Option{opt | help: help, flags: new_flags}
      # Validate option
      Artificery.Option.validate!(opt, caller: __MODULE__)

      case current_command do
        nil ->
          # Global
          Module.put_attribute(__MODULE__, :global_options, Map.put(global_options, option_name, opt))

        a when is_atom(a) ->
          # Top-level command
          cmd = Map.get(commands, current_command)
          cmd = Artificery.Command.add_option(cmd, opt)
          Module.put_attribute(__MODULE__, :commands, Map.put(commands, current_command, cmd))

        path when is_list(path) ->
          # Subcommand
          access_path = Enum.intersperse(path, :subcommands)
          cmd = get_in(commands, access_path)
          cmd = Artificery.Command.add_option(cmd, opt)
          commands = put_in(commands, access_path, cmd)
          Module.put_attribute(__MODULE__, :commands, commands)
      end
    end
  end

  # inline option with no help, e.g. `option :foo, :string`
  defmacro option(name, type) when is_atom(name) and is_atom(type) do
    quote location: :keep do
      option(unquote(name), unquote(type), nil, [])
    end
  end

  @doc """
  Similar to `defoption`, but defines an option inline. Options defined this way apply either to the global
  scope, if they aren't nested within a `command` macro, or to the scope of the command they are defined in.

  See `defoption` for usage examples.
  """
  defmacro option(name, type, flags) when is_atom(name) and is_atom(type) and is_list(flags) do
    quote location: :keep do
      option(unquote(name), unquote(type), nil, unquote(flags))
    end
  end
  defmacro option(name, type, help) when is_atom(name) and is_atom(type) do
    quote location: :keep do
      option(unquote(name), unquote(type), unquote(help), [])
    end
  end
  defmacro option(name, type, help, flags) when is_atom(name) and is_atom(type) and is_list(flags) do
    quote location: :keep do
      commands = Module.get_attribute(__MODULE__, :commands)
      current_command = var!(current_command, unquote(__MODULE__))
      global_options = Module.get_attribute(__MODULE__, :global_options)

      option_name = unquote(name)
      flags =
        Map.new(unquote(flags))
        |> Map.put(:type, unquote(type))
        |> Map.put(:help, unquote(help))
      opt = Artificery.Option.new(option_name, flags)
      Artificery.Option.validate!(opt, caller: __MODULE__)


      case current_command do
        nil ->
          # Global option
          Module.put_attribute(__MODULE__, :global_options, Map.put(global_options, option_name, opt))

        a when is_atom(a) ->
          # Top-level command option
          cmd = Map.get(commands, current_command)
          cmd = Artificery.Command.add_option(cmd, opt)
          Module.put_attribute(__MODULE__, :commands, Map.put(commands, current_command, cmd))

        path when is_list(path) ->
          # Subcommand option
          access_path = Enum.intersperse(path, :subcommands)
          cmd = get_in(commands, access_path)
          cmd = Artificery.Command.add_option(cmd, opt)
          commands = put_in(commands, access_path, cmd)
          Module.put_attribute(__MODULE__, :commands, commands)
      end
    end
  end

  @doc """
  Like `option`, but rather than a command switch, it defines a positional argument.

  Beyond the semantics of switches vs positional args, this takes the same configuration as `option` or `defoption`

  ## Example

      argument :name, :string
  """
  defmacro argument(name, type) when is_atom(name) and is_atom(type) do
    quote location: :keep do
      argument(unquote(name), unquote(type), nil, [])
    end
  end

  @doc """
  Like `argument/2`, but takes either help text or a keyword list of flags

  ## Example

      argument :name, :string, "The name to use"

      argument :name, :string, required: true
  """
  defmacro argument(name, type, help) when is_atom(name) and is_atom(type) and is_binary(help) do
    quote location: :keep do
      argument(unquote(name), unquote(type), unquote(help), [])
    end
  end
  defmacro argument(name, type, flags) when is_atom(name) and is_atom(type) and is_list(flags) do
    quote location: :keep do
      argument(unquote(name), unquote(type), nil, unquote(flags))
    end
  end

  @doc """
  Like `argument/3`, but takes a name, type, help text and keyword list of flags

  ## Example

      argument :name, :string, "The name to use", required: true
  """
  defmacro argument(name, type, help, flags) when
    is_atom(name) and is_atom(type) and (is_nil(help) or is_binary(help)) and is_list(flags) do
    quote location: :keep do
      commands = Module.get_attribute(__MODULE__, :commands)
      current_command = var!(current_command, unquote(__MODULE__))

      arg_name = unquote(name)
      flags =
        Map.new(unquote(flags))
        |> Map.put(:type, unquote(type))
        |> Map.put(:help, unquote(help))
      arg = Artificery.Option.new(arg_name, flags)
      Artificery.Option.validate!(arg, caller: __MODULE__)

      case current_command do
        nil ->
          raise "Cannot use `argument` macro outside of a command"

        a when is_atom(a) ->
          # Top-level command argument
          cmd = Map.get(commands, current_command)
          cmd = Artificery.Command.add_argument(cmd, arg)
          Module.put_attribute(__MODULE__, :commands, Map.put(commands, current_command, cmd))

        path when is_list(path) ->
          # Subcommand argument
          access_path = Enum.intersperse(path, :subcommands)
          cmd = get_in(commands, access_path)
          cmd = Artificery.Command.add_argument(cmd, arg)
          commands = put_in(commands, access_path, cmd)
          Module.put_attribute(__MODULE__, :commands, commands)
      end
    end
  end
end
