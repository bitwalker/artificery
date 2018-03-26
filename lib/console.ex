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

  if Mix.env == :test do
    # During tests we don't want to kill the node process,
    # exit the test process instead
    def halt(0), do: :ok
    def halt(code) when code >= 0, do: exit({:halt, code})
  else
    def halt(code) when code >= 0, do: System.halt(code)
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
  Prints a debug message, only visible when verbose mode is on
  """
  @spec debug(String.t()) :: :ok
  def debug(msg), do: log(:standard_error, :debug, colorize("==> #{msg}", [:cyan]))

  @doc """
  Prints an info message
  """
  @spec info(String.t()) :: :ok
  def info(msg), do: log(:stdio, :info, msg)

  @doc """
  Prints a notice
  """
  @spec notice(String.t()) :: :ok
  def notice(msg), do: log(:stdio, :info, colorize(msg, [:bright, :blue]))

  @doc """
  Prints a success message
  """
  @spec success(String.t()) :: :ok
  def success(msg), do: log(:stdio, :warn, colorize(msg, [:bright, :green]))

  @doc """
  Prints a warning message
  """
  @spec warn(String.t()) :: :ok
  def warn(msg), do: log(:standard_error, :warn, colorize(msg, [:yellow]))

  @doc """
  Prints an error message, and then halts the process
  """
  @spec error(String.t()) :: no_return
  def error(msg) do
    log(:standard_error, :error, colorize(bangify(msg), [:red]))
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
