defmodule Artificery.Console do
  @moduledoc "A minimal logger"

  alias __MODULE__.Events

  @doc """
  Initializes the logger configuration
  """
  @spec init() :: :ok
  def init do
    # For logger state
    :ets.new(__MODULE__, [:public, :set, :named_table])
    # Start listening for console events
    Events.start
    :ok
  end

  @doc """
  Gets the current width of the terminal in columns
  """
  @spec width() :: non_neg_integer
  def width do
    case :io.columns() do
      {:error, :enotsup} -> 80
      {:ok, cols} when cols < 30 -> 30
      {:ok, cols} -> cols
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

  defp log(device, level, msg), do: log(device, level, get_verbosity(), msg)
  defp log(device, _, :debug, msg), do: IO.write(device, [msg, ?\n])
  defp log(_device, :debug, :info, _msg), do: :ok
  defp log(device, _, _, msg), do: IO.write(device, [msg, ?\n])

  defp colorize(msg, styles) when is_list(styles), do: __MODULE__.Color.style(msg, styles)

  defp get_verbosity(), do: get_verbosity(:ets.lookup(__MODULE__, :level))
  defp get_verbosity([]), do: :info
  defp get_verbosity([{_, v}]), do: v

  if Mix.env == :test do
    defp halt(code), do: exit({:halt, code})
  else
    defp halt(code), do: System.halt(code)
  end

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
end
