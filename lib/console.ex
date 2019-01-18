defmodule Artificery.Console do
  @moduledoc "A minimal logger"

  alias __MODULE__.Events

  @esc "\u001B["
  @cursor_left @esc <> "G"
  @cursor_hide @esc <> "?25l"
  @cursor_show @esc <> "?25h"
  @erase_line @esc <> "2K"
  #@erase_down @esc <> "J"

  @doc """
  Terminates the process with the given status code
  """
  @spec halt(non_neg_integer) :: no_return
  def halt(code)

  def halt(0), do: :ok
  def halt(code) when code > 0 do
    if Application.get_env(:artificery, :no_halt, false) do
      # During tests we don't want to kill the node process,
      # exit the test process instead
      exit({:halt, code})
    else
      System.halt(code)
    end
  end

  @doc """
  Updates the logger configuration with the given options.
  """
  @spec configure(Keyword.t()) :: Keyword.t()
  def configure(opts) when is_list(opts) do
    verbosity = Keyword.get(opts, :verbosity)
    :ets.insert(__MODULE__, {:level, verbosity})
    opts
  end

  @doc """
  Ask the user a question which requires a yes/no answer, returns a boolean
  """
  defdelegate yes?(question), to: __MODULE__.Prompt

  @doc """
  Ask the user to provide data in response to a question

  The value returned is dependent on whether a transformation is applied,
  and whether blank answers are accepted. By default, empty strings will
  return nil if no alternate default is supplied and either no validator
  was supplied, or it returned `:ok` for blank answers.

  If you supply a default, instead of nil, the default will be returned.
  Again this only applies if a blank answer is considered valid.

  You may validate answers by supplying a function (bound or captured) via
  the `validator: fun` option. This function will receive the raw input string
  supplied by the user, and should return `:ok` if the answer is valid, or
  `{:error, validation_error}`, where `validation_error` is a string which will
  be displayed to the user before asking them to answer the question again.

  You may apply a transformation to answers, so that rather than getting a
  string back, you get the value in a state useful for your application. You may
  provide a transform via the `transform: fun` option, and this will receive the
  raw input string the user provided _after_ the validator has validated the input,
  if one was supplied, and if the user input was non-nil.

  Supply default values with the `default: term` option
  """
  defdelegate ask(question, opts \\ []), to: __MODULE__.Prompt

  @doc """
  Write text or iodata to standard output.

  You may optionally pass a list of styles to apply to the output, as well
  as the device to write to (:standard_error, or :stdio)
  """
  @spec write(iodata) :: :ok
  @spec write(iodata, [atom]) :: :ok
  @spec write(:standard_error | :stdio, iodata, [atom]) :: :ok
  def write(msg), do: write(:stdio, msg, [])
  def write(msg, styles) when is_list(styles), do: write(:stdio, msg, styles)
  def write(device, msg, styles) when is_list(styles) do
    IO.write(device, Artificery.Console.Color.style(msg, styles))
  end

  @doc """
  Prints a debug message, only visible when verbose mode is on
  """
  @spec debug(String.t()) :: :ok
  @spec debug(:standard_error | :stdio, String.t()) :: :ok
  def debug(device \\ :stdio, msg),
    do: log(device, :debug, colorize("==> #{msg}", [:cyan]))

  @doc """
  Prints an info message
  """
  @spec info(String.t()) :: :ok
  @spec info(:standard_error | :stdio, String.t()) :: :ok
  def info(device \\ :stdio, msg), 
    do: log(device, :info, msg)

  @doc """
  Prints a notice
  """
  @spec notice(String.t()) :: :ok
  @spec notice(:standard_error | :stdio, String.t()) :: :ok
  def notice(device \\ :stdio, msg), 
    do: log(device, :info, colorize(msg, [:bright, :blue]))

  @doc """
  Prints a success message
  """
  @spec success(String.t()) :: :ok
  @spec success(:standard_error | :stdio, String.t()) :: :ok
  def success(device \\ :stdio, msg), 
    do: log(device, :warn, colorize(msg, [:bright, :green]))

  @doc """
  Prints a warning message
  """
  @spec warn(String.t()) :: :ok
  @spec warn(:standard_error | :stdio, String.t()) :: :ok
  def warn(device \\ :stdio, msg), 
    do: log(device, :warn, colorize(msg, [:yellow]))

  @doc """
  Prints an error message, and then halts the process
  """
  @spec error(String.t()) :: no_return
  @spec error(:standard_error | :stdio, String.t()) :: no_return
  def error(device \\ :stdio, msg) do
    log(device, :error, colorize(bangify(msg), [:red]))
    halt(1)
  end

  @doc """
  Provides a spinner while some long-running work is being done.

  ## Options

  - spinner: one of the spinners defined in Artificery.Console.Spinner

  ## Example

      Console.spinner "Loading...", [spinner: :simple_dots] do
        :timer.sleep(5_000)
      end
  """
  defmacro spinner(msg, opts \\ [], do: block) when is_binary(msg) do
    quote location: :keep do
      {:ok, spinner} = Artificery.Console.Spinner.start_link(unquote(opts))
      Artificery.Console.Spinner.start(spinner)
      loop = fn loop, pid ->
        receive do
          {^pid, {:ok, res}} ->
            Artificery.Console.Spinner.stop(spinner)
            res
          {^pid, {:error, {type, err, trace}}} ->
            Artificery.Console.Spinner.stop(spinner)
            Artificery.Console.error(Exception.format(type, err, trace))
          {^pid, {:exception, {err, trace}}} ->
            Artificery.Console.Spinner.stop(spinner)
            msg = Exception.message(err) <> Exception.format_stacktrace(trace)
            Artificery.Console.error(msg)
        after
          1_000 ->
            loop.(loop, pid)
        end
      end
      parent = self()
      pid = spawn(fn ->
        try do
          res = unquote(block)
          send parent, {self(), {:ok, res}}
        rescue
          err ->
            send parent, {self(), {:exception, {err, System.stacktrace}}}
        catch
          type, err ->
            send parent, {self(), {:error, {type, err, System.stacktrace}}}
        end
      end)
      loop.(loop, pid)
    end
  end

  @doc """
  Updates a running spinner with the provided status text
  """
  @spec update_spinner(String.t) :: :ok
  def update_spinner(status) when is_binary(status) do
    Artificery.Console.Spinner.status(status)
  end

  # Used for tests
  @doc false
  def update_spinner(spinner, status) do
    Artificery.Console.Spinner.status(spinner, status)
  end

  @doc false
  def show_cursor(), do: IO.write([@cursor_show])

  @doc false
  def hide_cursor(), do: IO.write([@cursor_hide])

  # Move the cursor up the screen by `n` lines
  @doc false
  def cursor_up(n), do: IO.write([@esc, "#{n}A"])

  # Move the cursor down the screen by `n` lines
  @doc false
  def cursor_down(n), do: IO.write([@esc, "#{n}B"])

  # Move the cursor right on the screen by `n` columns
  @doc false
  def cursor_forward(n), do: IO.write([@esc, "#{n}C"])

  # Move the cursor left on the screen by `n` columns
  @doc false
  def cursor_backward(n), do: IO.write([@esc, "#{n}D"])

  # Move the cursor to the next line
  @doc false
  def cursor_next_line, do: IO.write([@esc, "E"])

  # Move the cursor to the previous line
  @doc false
  def cursor_prev_line, do: IO.write([@esc, "F"])

  # Erases the current line, placing the cursor at the beginning
  @doc false
  def erase_line, do: IO.write([@cursor_left, @erase_line])

  # Erases `n` lines starting at the current line and going up the screen
  @doc false
  def erase_lines(0), do: ""
  def erase_lines(n) when is_integer(n) do
    erase_line()
    if (n - 1) > 0 do
      cursor_up(1)
    end
    erase_lines(n - 1)
  end

  defp log(device, level, msg), do: log(device, level, get_verbosity(), msg)
  defp log(device, _, :debug, msg), do: IO.write(device, [msg, ?\n])
  defp log(_device, :debug, :info, _msg), do: :ok
  defp log(device, _, _, msg), do: IO.write(device, [msg, ?\n])

  defp colorize(msg, styles) when is_list(styles), do: __MODULE__.Color.style(msg, styles)

  defp get_verbosity(), do: get_verbosity(:ets.lookup(__MODULE__, :level))
  defp get_verbosity([]), do: :info
  defp get_verbosity([{_, v}]), do: v

  defp arrow do
    case :os.type() do
      {:win32, _} ->
        ?!
      _ ->
        ?▸
    end
  end

  defp bangify(msg, c \\ arrow()) do
    lines =
    for line <- String.split(msg, "\n", trim: true) do
      [c, ?\s, ?\s, line]
    end
    Enum.join(lines, "\n")
  end

  @doc false
  @spec init() :: :ok
  def init do
    # For logger state
    :ets.new(__MODULE__, [:public, :set, :named_table])
    # Start listening for console events
    Events.start
    :ok
  end

  @doc false
  @spec width() :: non_neg_integer
  def width do
    case :io.columns() do
      {:error, :enotsup} -> 80
      {:ok, cols} when cols < 30 -> 30
      {:ok, cols} -> cols
    end
  end
end
