# Artificery

Artificery is a toolkit for generating command line applications. It handles argument parsing, validation/transformation,
generating help, and provides an easy way to define commands, their arguments, and options.

## Installation

Just add Artificery to your deps:

```elixir
defp deps do
  [
    # You can get the latest version information via `mix hex.info artificery`
    {:artificery, "~> x.x"}
  ]
end
```

Then run `mix deps.get` and you are ready to get started!

## Defining a CLI

Let's assume you have an application named `:myapp`, let's define a module, `MyCliModule` which
will be the entry point for the command line interface:

```elixir
defmodule MyCliModule do
  use Artificery
end
```

The above will setup the Artificery internals for your CLI, namely it defines an entry point for the command line,
argument parsing, and imports the macros for defining commands, options, and arguments.

### Commands

Let's add a simple "hello" command, which will greet the caller:

```elixir
defmodule MyCliModule do
  use Artificery
  
  command :hello, "Says hello" do
    argument :name, :string, "The name of the person to greet", required: true
  end
end
```

We've introduced two of the macros Aritificery imports: `command`, for defining top-level and nested commands; and
`argument` for defining positional arguments for the current command. **Note**: `argument` can only be used inside of
`command`, as it applies to the current command being defined, and has no meaning globally.

This command could be invoked (via escript) like so: `./myapp hello bitwalker`. Right now this will print an error stating
that the command is defined, but no matching implementation was exported. We define that like so:

```elixir
def hello(_argv, %{name: name}) do
  Artificery.Console.notice "Hello #{name}!"
end
```

**Note**: Command handlers are expected to have an arity of 2, where the first argument is a list of unhandled arguments/options passed on
the command line, and the second is a map containing all of the formally defined arguments/options.

This goes in the same module as the command definition, but you can use `defdelegate` to put the implementation elsewhere. The thing
to note is that the function needs to be named the same as the command. You can change this however using an extra parameter to `command`,
like so:

```elixir
command :hello, [callback: :say_hello], "Says hello" do
  argument :name, :string, "The name of the person to greet", required: true
end
```

The above will invoke `say_hello/2` rather than `hello/2**.

### Command Flags

There are two command flags you can set currently to alter some of Artificery's behaviour: `callback: atom` and
`hidden: boolean`. The former will change the callback function invoked when dispatching a command, as shown above,
and the latter, when true, will hide the command from display in the `help` output. You may also apply `:hidden` to
options (but not arguments).

### Options

Let's add a `--greeting=string` option to the `hello` command:

```elixir
command :hello, "Says hello" do
  argument :name, :string, "The name of the person to greet", required: true
  option :greeting, :string, "Sets a different greeting than \"Hello <name>\!""
end
```

And adjust our implementation:

```elixir
def hello(_argv, %{name: name} = opts) do
  greeting = Map.get(opts, :greeting, "Hello")
  greet(greeting, name)
end
defp greet(greeting, name), do: Artificery.Console.notice("#{greeting} #{name}!")
```

And we're done!

### Subcommands

When you have more complex command line interfaces, it is common to divide up "topics" or top-level commands into subcommands,
you see this in things like Heroku's CLI, e.g. `heroku keys:add`. Artificery supports this by allowing you to nest `command` 
within another `command`. Artificery is smart about how it parses arguments, so you can have options/arguments at the top-level
as well as in subcommands, e.g. `./myapp info --format=json processes`. The options map received by the `processes` command
will contain all of the options for commands above it.

```elixir
defmodule MyCliModule do
  use Artificery
  
  command :info, "Get info about :myapp" do
    option :format, :string, "Sets the output format"
    
    command :processes, "Prints information about processes running in :myapp"
  end
```

**Note**: As you may have noticed above, the `processes` command doesn't have a `do` block, because it
doesn't define any arguments or options, this form is supported for convenience


### Global Options

You may define global options which apply to all commands by defining them outside `command`:

```elixir
defmodule MyCliModule do
  use Artificery
  
  option :debug, :boolean, "When set, produces debugging output"
  
  ...
end
```

Now all commands defined in this module will receive `debug: true | false` in their options map,
and can act accordingly.

### Reusing Options

You can define reusable options via `defoption/3` or `defoption/4`. These are effectively the same as
`option/3` and `option/4`, except they do not define an option in any context, they are defined abstractly
and intended to be used via `option/1` or `option/2`, as shown below:

```elixir
defoption :host, :string, "The hostname of the server to connect to",
  alias: :h

command :ping, "Pings the host to verify connectivity" do
  # With no overridden flags
  # option :host
  
  # With overrides
  option :host, help: "The host to ping", default: "localhost"
end

command :query, "Queries the host" do
  # Can be shared across commands, even used globally
  option :host, required: true
  argument :query, :string, required: true
end
```

### Option/Argument Transforms

You can provide transforms for options or arguments to convert them to the data types your commands desire as part of
the option definition, like so:

```elixir
# Options
option :ip, :string, "The IP address of the host to connect to",
  transform: fn raw ->
    case :inet.parse_address(String.to_charlist(raw)) do
      {:ok, ip} ->
        ip
      {:error, reason} ->
        raise "invalid value for --ip, got: #{raw}, error: #{inspect reason}"
    end
  end
  
# Arguments
argument :ip, :string, "The IP address of the host to connect to",
  transform: ...
```

Now the command (and any subcommands) where this option is defined will get a parsed IP address, rather than
a raw string, allowing you to do the conversion in one place, rather than in each command handler.

Currently this macro supports functions in anonymous form (like in the example above), or one of the following forms:

```elixir
# Function capture, must have arity 1
transform: &String.to_atom/1

# Local function as an atom, must have arity 1
transform: :to_ip_address

# Module/function/args tuple, where the raw value is passed as the first argument
# This form is invoked via `apply/3`
transform: {String, :to_char_list, []}
```

### Pre-Dispatch Handling

For those cases where you need to perform some action before command handlers are invoked,
perhaps to apply global behaviour to all commands, start applications, or whatever else you may need,
Artificery provides a hook for that, `pre_dispatch/3`.

This is actually a callback defined as part of the `Artificery` behaviour, but is given a default
implementation. You can override this implementation though to provide your own pre-dispatch step.

The default implementation is basically the following:

```elixir
def pre_dispatch(%Artificery.Command{}, _argv, %{} = options) do
  {:ok, options}
end
```

You can either return `{:ok, options}` or raise an error, there are no other choices permitted. This
allows you to extend or filter `options`, handle additional arguments in `argv`, or take action based
on the current command.

## Writing Output / Logging

Artificery provides a `Console` module which contains a number of functions for logging or writing output
to standard out/standard error. A list of basic functions it provides is below:

- `configure/1`, takes a list of options which configures the logger, currently the only option is `:verbosity`
- `debug/1`, writes a debug message to stderr (colored cyan if terminal supports color)
- `info/1`, writes an info message to stdout (no color)
- `notice/1`, writes an informatinal notice to stdout (bright blue)
- `success/1`, writes a success message to stdout (bright green)
- `warn/1`, writes a warning to stderr (yellow)
- `error/1`, writes an error to stderr (red), and also halts/terminates the process with a non-zero exit code

In addition to writing messages to the terminal, `Console` also provides a way to provide a spinner/loading animation
while some long-running work is being performed, also supporting the ability to update the message with progress information.

The following example shows a trivial example of progress, by simply reading from a file in a loop, updating the status
of the spinner while it reads. There are obviously cleaner ways of writing this, but hopefully it is clear what the capabilities are.

```elixir
def load_data(_argv, %{path: path}) do
  alias Artificery.Console
  
  unless File.exists?(path) do
    Console.error "No such file: #{path}"
  end
  
  # A state machine defined as a recursive anonymous function
  # Each state updates the spinner status and is reflected in the console
  loader = fn 
    :opening, _size, _bytes_read, _file, loader ->
      Console.update_spinner("opening #{path}")
      %{size: size} = File.stat!(path)
      loader.(:reading, size, 0, File.open!(path), loader)

    :reading, size, bytes_read, file, loader ->
      progress = Float.round((size / bytes_read) * 100)
      Console.update_spinner("reading..#{progress}%")
      case IO.read(file) do
        :eof ->
          loader.(:done, size, bytes_read, file, loader)

        {:error, _reason} = err ->
          Console.update_spinner("read error!")
          File.close!(file)
          err

        new_data ->
          loader.(:reading, size, byte_size(new_data), file, loader)
      end

    :done, size, bytes_read, file, loader ->
      Console.update_spinner("done! (total bytes read #{bytes_read})")
      File.close!(file)
      :ok
  end

  results =
    Console.spinner "Loading data.." do
      loader.(:opening, 0, 0, nil, loader)
    end

  case results do
    {:error, reason} ->
      Console.error "Failed to load data from #{path}: #{inspect reason}"

    :ok ->
      Console.success "Load complete!"
  end
end
```

## Handling Input

Artificery exposes some functions for working with interactive user sessions:

- `yes?/1`, asks the user a question and expects a yes/no response, returns a boolean
- `ask/2`, queries the user for information they need to provide

### Example

Let's shoot for a slightly more amped up `hello` command:

```elixir
def hello(_argv, _opts) do
  name = Console.ask "What is your name?", validator: &is_valid_name/1
  Console.success "Hello #{name}!"
end

defp is_valid_name(name) when byte_size(name) > 1, do: :ok
defp is_valid_name(_), do: {:error, "You must tell me your name or I can't greet you!"}
```

The above will accept any name more than one character in length, obviously not super robust, but the general idea is shown here.
The `ask` function also supports transforming responses, and providing defaults in the case where you want to accept blank answers.
Check the docs for more information!

## Producing An Escript

To use your newly created CLI as an escript, simply add the following to your `mix.exs`:

```elixir
defp project do
  [
    ...
    escript: escript()
  ]
end

...

defp escript do
  [main_module: MyCliModule]
end
```

The `main_module` to use is the module in which you added `use Artificery`, i.e. the module in
which you defined the commands your application exposes.

Finally, run `mix escript.build` to generate the escript executable. You can then run `./yourapp help` to test it out.

## Using In Releases

If you want to define the CLI as part of a larger application, and consume it via custom commands in Distillery, it is
very straightforward to do. You'll need to define a custom command and add it to your release configuration:

```elixir

# rel/config.exs

release :myapp do
  set commands: [
    mycli: "rel/commands/mycli.sh"
  ]
end
```

Then in `rel/commands/mycli.sh` add the following:

```shell
#!/usr/bin/env bash

elixir -e "MyCliModule.main" -- "$@"
```

Since the code for your application will already be on the path in a release, we simply need to invoke the CLI module and pass in arguments.
We add `--` between the `elixir` arguments and those provided from the command line to ensure that they are not treated like arguments to our
CLI. Artificery handles this, so you simply need to ensure that you add `--` when invoking via `elixir` like this.

You can then invoke your CLI via the custom command, for example, `bin/myapp mycli help` to print the help text.

## Roadmap

- [ ] Support validators

I'm open to suggestions, just open an issue titled `RFC: <feature you are requesting>`

## License

This project is licensed under Apache 2.0

See the LICENSE file in this repository for details.
