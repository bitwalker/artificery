defmodule Artificery.Entry do
  @moduledoc """
  This module defines the entrypoint for Artificery command line applications,
  which handles argument parsing, dispatch, and help generation.
  """

  @doc false
  defmacro __before_compile__(_env) do
    # Are we building an escript?
    escript? =
      :init.get_plain_arguments()
      |> Enum.map(&List.to_string/1)
      |> Enum.any?(fn
        "escript.build" -> true
        _ -> false
      end)

    script_name =
      if escript? do
        Mix.Local.name_for(:escripts, Mix.Project.config())
      else
        "elixir -e \"#{__CALLER__.module}.main\" -- "
      end

    quote location: :keep do
      alias Artificery.{Console, Command}

      @doc """
      Main entry point for this script.

      Handles parsing and validating arguments, then dispatching the selected command
      """
      def main() do
        argv =
          :init.get_plain_arguments()
          |> Enum.map(&List.to_string/1)
          |> Enum.drop_while(fn arg -> arg != "--" end)
          |> Enum.drop(1)

        main(argv)
      end

      @doc false
      def main(argv) when is_list(argv) do
        Console.init()

        parse_args(argv)

        Console.halt(0)
      end

      def parse_args(argv) do
        switches =
          for {opt_name, opt_config} <- @global_options do
            {opt_name, Map.get(opt_config, :type, :string)}
          end

        aliases =
          for {opt_name, opt_config} <- @global_options,
              a = Map.get(opt_config, :alias),
              is_atom(a) and not is_nil(a) do
            {a, opt_name}
          end

        parser_opts = [strict: switches, aliases: aliases]

        {global_flags, argv, nonglobal_flags} = OptionParser.parse_head(argv, parser_opts)

        argv =
          case nonglobal_flags do
            [] ->
              argv

            [{flag, _}] ->
              [flag | argv]
          end

        global_flags_base =
          @global_options
          |> Enum.map(fn {name, opt} -> {name, opt.flags[:default]} end)
          |> Enum.filter(fn {_, default} -> not is_nil(default) end)

        # Merge set flags over defaults, apply transforms, convert to map
        global_flags =
          global_flags_base
          |> Keyword.merge(global_flags)
          |> Enum.map(fn {name, val} -> {name, apply_transform(@global_options[name], val)} end)
          |> Map.new()

        Console.configure(verbosity: Map.get(global_flags, :verbose, :normal))

        case argv do
          [] ->
            print_help([])

          ["help" | rest] ->
            print_help(rest)

          ["--" <> flag | _] ->
            Console.error("Unknown global option '--#{flag}'. Try 'help' for usage information")

          [command_name | _] ->
            command_name = String.to_atom(command_name)

            # Check for valid command
            if Map.has_key?(@commands, command_name) do
              parse_args(argv, nil, global_flags)
            else
              Console.error("Unknown command '#{command_name}'. Try 'help' for usage information")
            end
        end
      end

      defp parse_args([], cmd, flags) do
        post_process_command(cmd, [], flags)
      end

      defp parse_args([command_name | argv] = oargv, context_cmd, flags) do
        commands =
          case context_cmd do
            nil ->
              for {k, v} <- @commands, do: {Atom.to_string(k), v}, into: %{}

            %{subcommands: subcommands} ->
              for {k, v} <- subcommands, do: {Atom.to_string(k), v}, into: %{}
          end

        arguments =
          case context_cmd do
            nil ->
              []

            %{arguments: arguments} ->
              arguments
          end

        has_subcommands = map_size(commands) > 0
        has_arguments = length(arguments) > 0

        case Map.get(commands, command_name) do
          nil when is_nil(context_cmd) ->
            Console.error("Unknown command '#{command_name}'. Try 'help' for usage information")

          nil when command_name == "help" ->
            print_help(argv)

          # This means the current argument is not a subcommand name
          nil when not has_arguments and has_subcommands ->
            Console.error(
              "Unknown subcommand '#{command_name}'. Try 'help' for usage information"
            )

          # This means the current argument is not a subcommand name,
          # but should instead be considered a positional argument
          nil when has_arguments ->
            # Pop the first argument off
            [arg | arguments] = arguments

            # Rename this to prevent confusion
            arg_val = command_name

            # Perform translation
            new_arg_val = apply_transform(arg, arg_val)

            # Should we accumulate?
            accumulate? = arg.flags[:accumulate] || false

            new_arg_val =
              case Map.get(flags, arg.name) do
                nil when accumulate? ->
                  # Wrap in list
                  [new_arg_val]

                nil ->
                  # Nothing to do
                  new_arg_val

                old_value when is_list(old_value) ->
                  # Append to list
                  old_value ++ [new_arg_val]
              end

            # Update flags
            new_flags = Map.put(flags, arg.name, new_arg_val)
            # Recur by removing an argument from the stack and updating the flags
            parse_args(argv, %{context_cmd | arguments: arguments}, new_flags)

          # No subcommands and no defined positional arguments
          # Just pass the plain argv to the command in case it wants them
          nil ->
            post_process_command(context_cmd, oargv, flags)

          # We found a matching subcommand
          cmd when is_map(cmd) ->
            post_process_command(cmd, argv, flags)
        end
      end

      defp post_process_command(%{options: command_opts} = cmd, argv, flags) do
        command_name = cmd.name

        switches =
          for {opt_name, opt_config} <- command_opts do
            {opt_name, Map.get(opt_config, :type, :string)}
          end

        aliases =
          for {opt_name, opt_config} <- command_opts,
              a = Map.get(opt_config, :alias),
              is_atom(a) and not is_nil(a) do
            {a, opt_name}
          end

        required =
          for {name, opt} <- command_opts, opt.flags[:required] == true do
            name
          end

        parser_opts = [strict: switches, aliases: aliases]

        # Split on -- so we can properly handle passing raw arguments to commands
        {argv, extra_argv} =
          Enum.split_while(argv, fn
            "--" -> false
            _ -> true
          end)

        {new_flags, new_argv, _invalid} = OptionParser.parse_head(argv, parser_opts)
        new_argv = new_argv ++ extra_argv

        has_arguments? = length(cmd.arguments) > 0

        # Enforce required options
        for required_flag <- required do
          if is_nil(Keyword.get(new_flags, required_flag)) and
               is_nil(Map.get(flags, required_flag)) do
            formatted_flag = format_flag(required_flag)

            Console.error(
              "Missing required flag '#{formatted_flag}'. Try 'help #{command_name}' for usage information"
            )
          end
        end

        # We backfill defaults only if not already provided
        base_new_flags =
          command_opts
          |> Enum.map(fn {name, opt} -> {name, opt.flags[:default]} end)
          |> Enum.filter(fn {_, default} -> not is_nil(default) end)
          |> Map.new()
          |> Map.merge(flags)

        # Run transforms on newly parsed flags
        new_flags =
          new_flags
          |> Enum.map(fn {name, val} -> {name, apply_transform(command_opts[name], val)} end)
          |> Map.new()

        # Merge over the top of the base flags (i.e. those already set)
        new_flags = Map.merge(base_new_flags, new_flags)

        cond do
          # No arguments, so dispatch
          length(new_argv) == 0 ->
            dispatch(cmd, [], new_flags)

          # The remaining arguments should be given to the command
          match?(["--" | _], new_argv) ->
            dispatch(cmd, tl(new_argv), new_flags)

          # Has arguments that need processing
          new_argv == argv and has_arguments? ->
            parse_args(new_argv, cmd, new_flags)

          # Extra arguments, so just dispatch with remaining argv
          new_argv == argv ->
            dispatch(cmd, new_argv, new_flags)

          # Arguments changed during option parsing, so go back to parse_args
          :else ->
            parse_args(new_argv, cmd, new_flags)
        end
      end

      defp dispatch(%Command{name: command_name, callback: callback} = command, argv, flags) do
        new_flags =
          case __MODULE__.pre_dispatch(command, argv, flags) do
            {:ok, new_flags} ->
              new_flags

            other ->
              Console.error(
                "Expected {:ok, options} returned from #{__MODULE__}.pre_dispatch/3, got: #{
                  inspect(other)
                }"
              )
          end

        if function_exported?(__MODULE__, callback, 2) do
          apply(__MODULE__, callback, [argv, new_flags])
        else
          Console.error(
            "Command definition found for '#{command_name}', but #{__MODULE__}.#{callback}/2 is not exported!"
          )
        end
      end

      defp script_name() do
        candidate =
          :init.get_plain_arguments()
          |> List.first()
          |> List.to_string()

        if File.exists?(candidate) do
          Path.basename(candidate)
        else
          Atom.to_string(__MODULE__)
          |> String.replace("Elixir.", "")
        end
      end

      defp print_help([]) do
        # Print global help

        # Header
        IO.write("#{script_name()} - A release utility tool\n\n")

        IO.write([
          "USAGE",
          ?\n,
          "  $ #{unquote(script_name)} [global_options] <command> [options..] [args..]",
          ?\n,
          ?\n
        ])

        IO.write("GLOBAL OPTIONS\n\n")

        # Print global options
        global_options = format_flags(@global_options)
        {flag_width, help_width} = column_widths(global_options)

        for {flag, help} <- global_options do
          IO.write([flag, String.duplicate(" ", max(flag_width - byte_size(flag) + 2, 2))])
          print_help_lines(help, flag_width + 2)
        end

        IO.write([?\n, "COMMANDS\n\n"])

        # Print commands
        commands = format_commands(@commands)
        {cmd_width, help_width} = column_widths(commands)

        for {cmd, help} <- commands do
          IO.write([cmd, String.duplicate(" ", max(cmd_width - byte_size(cmd) + 2, 2))])
          [first | rest] = String.split(help, "\n", trim: true, parts: 2)

          if length(rest) > 0 do
            IO.write([first, ?\s, "...", ?\n])
          else
            IO.write([first, ?\n])
          end
        end

        Console.halt(1)
      end

      defp print_help([command_name | argv]) do
        commands = @commands

        command_path =
          case extract_command_path(commands, [command_name | argv], []) do
            [] ->
              # Not actually a subcommand path, so print top level help
              print_help([])

            path ->
              path
          end

        full_command_name =
          command_path
          |> Enum.map(&Atom.to_string/1)
          |> Enum.join(" ")

        # Validate command
        cmd = get_in(commands, Enum.intersperse(command_path, :subcommands))

        if is_nil(cmd) do
          Console.error("No such command '#{full_command_name}'")
        end

        help_text = cmd[:help]

        has_opts? = map_size(cmd.options) > 0
        has_args? = length(cmd.arguments) > 0
        has_help? = not is_nil(help_text) and byte_size(help_text) > 0

        has_subcommands? =
          cmd.subcommands
          |> Enum.reject(fn {_name, %{hidden: hidden}} -> hidden end)
          |> Enum.count() > 0

        # Header
        if has_help? do
          IO.write([help_text, ?\n, ?\n])
        end

        if has_args? do
          IO.write([
            "USAGE",
            ?\n,
            "  $ #{unquote(script_name)} #{full_command_name} [options..] [args..]\n\n"
          ])
        else
          IO.write([
            "USAGE",
            ?\n,
            "  $ #{unquote(script_name)} #{full_command_name} [options..]\n\n"
          ])
        end

        # Print subcommands
        if has_subcommands? do
          IO.write("SUBCOMMANDS\n")

          # Print commands
          commands = format_commands(cmd.subcommands)
          {cmd_width, help_width} = column_widths(commands)

          for {subcmd, help} <- commands do
            IO.write([subcmd, String.duplicate(" ", max(cmd_width - byte_size(subcmd) + 2, 2))])
            [first | rest] = String.split(help, "\n", trim: true, parts: 2)

            if length(rest) > 0 do
              IO.write([first, ?\s, "...", ?\n])
            else
              IO.write([first, ?\n])
            end
          end

          IO.write("\n")
        end

        # Print options
        if has_opts? do
          IO.write("OPTIONS\n")

          options = format_flags(cmd.options)
          {flag_width, help_width} = column_widths(options)

          for {flag, help} <- options do
            IO.write([flag, String.duplicate(" ", max(flag_width - byte_size(flag) + 2, 2))])
            print_help_lines(help, flag_width + 2)
          end

          if has_args?, do: IO.write("\n")
        end

        # Print arguments
        if has_args? do
          IO.write("ARGUMENTS\n")

          arguments = format_arguments(cmd.arguments)
          {arg_width, help_width} = column_widths(arguments)

          for {arg, help} <- arguments do
            IO.write([arg, String.duplicate(" ", max(arg_width - byte_size(arg) + 2, 2))])
            print_help_lines(help, arg_width + 2)
          end
        end

        Console.halt(1)
      end

      defp extract_command_path(_commands, [], acc), do: Enum.reverse(acc)

      defp extract_command_path(commands, [command_name | argv], acc) do
        command_name = String.to_atom(command_name)

        case get_in(commands, [command_name]) do
          nil ->
            Enum.reverse(acc)

          %{subcommands: subcommands} = cmd ->
            {_, new_argv, _} = OptionParser.parse_head(argv, [])
            extract_command_path(subcommands, new_argv, [command_name | acc])
        end
      end

      defp print_help_lines("", _leading_width) do
        IO.write("\n")
      end

      defp print_help_lines(content, leading_width) do
        [first | rest] = String.split(content, "\n", trim: true)
        IO.write([first, ?\n])

        for line <- rest do
          IO.write([String.duplicate(" ", leading_width), line, ?\n])
        end
      end

      defp format_arguments(args) do
        for {name, opt} <- args do
          {"    #{name}", opt.help || ""}
        end
      end

      defp format_flags(flags) do
        for {name, opt} <- flags do
          type = opt.type
          opt_alias = opt.flags[:alias]
          default = opt.flags[:default]
          help = opt.help

          help =
            cond do
              is_nil(default) ->
                help

              byte_size(help) > 0 and type == :string ->
                help <> " (default: \"#{default}\")"

              byte_size(help) > 0 ->
                help <> " (default: #{default})"

              type == :string ->
                "(default: \"#{default}\")"

              :else ->
                "(default: #{default})"
            end

          flag =
            cond do
              type == :boolean and not is_nil(opt_alias) ->
                "  #{format_alias(opt_alias)}, #{format_flag(name)}"

              type == :boolean ->
                "  #{format_flag(name)}"

              not is_nil(opt_alias) ->
                "  #{format_alias(opt_alias)}, #{format_flag(name)}=#{opt.type}"

              :else ->
                "  #{format_flag(name)}=#{opt.type}"
            end

          {flag, help || ""}
        end
      end

      defp format_flag(name) when is_atom(name) do
        format_flag(Atom.to_string(name))
      end

      defp format_flag(name) when is_binary(name) do
        "--#{String.replace(name, "_", "-")}"
      end

      @valid_aliases Enum.concat(?a..?z, ?A..?Z)
      defp format_alias(opt_alias) when is_atom(opt_alias) do
        format_alias(Atom.to_string(opt_alias))
      end

      defp format_alias(<<letter::utf8>>) when letter in @valid_aliases do
        <<?-, letter::utf8>>
      end

      defp format_alias(opt_alias) when is_binary(opt_alias) do
        raise "Invalid alias `#{opt_alias}`, must be one character in the range a-zA-Z"
      end

      defp format_commands(commands) do
        for {name, opt} <- commands, not opt.hidden do
          {"  #{name}", opt.help || ""}
        end
      end

      defp column_widths([]), do: {0, 0}

      defp column_widths(items) do
        cols =
          items
          |> Enum.map(&Tuple.to_list/1)
          |> Enum.map(fn cols -> Enum.map(cols, &byte_size/1) end)
          |> List.zip()
          |> Enum.map(&Tuple.to_list/1)

        acc = :erlang.make_tuple(length(cols), 0)

        cols
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {rows, i}, acc ->
          :erlang.setelement(i + 1, acc, Enum.max(rows))
        end)
      end

      defp indent(content, spaces) do
        pad = String.duplicate(" ", spaces)

        content =
          content
          |> String.split("\n", trim: true)
          |> Enum.intersperse("\n" <> pad)
          |> Enum.join("")

        [pad, content]
      end

      defp apply_transform(%Artificery.Option{flags: %{transform: transform}}, value) do
        case transform do
          nil ->
            value

          f when is_function(f, 1) ->
            f.(value)

          a when is_atom(a) ->
            apply(__MODULE__, a, [value])

          {m, f, a} when is_atom(m) and is_atom(f) and is_list(a) ->
            apply(m, f, [value | a])
        end
      end

      defp apply_transform(%Artificery.Option{}, value), do: value
    end
  end
end
