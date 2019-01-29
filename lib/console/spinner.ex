defmodule Artificery.Console.Spinner do
  @moduledoc false

  alias Artificery.Console.Color.ANSI

  @esc "\u001B["
  @cursor_left @esc <> "G"
  @cursor_hide @esc <> "?25l"
  @cursor_show @esc <> "?25h"
  @erase_line @esc <> "2K"
  @erase_down @esc <> "J"

  @spinners %{
    bouncing_bar: %{
      interval: 80,
      frames: [
        "[    ]",
        "[   =]",
        "[  ==]",
        "[ ===]",
        "[====]",
        "[=== ]",
        "[==  ]",
        "[=   ]"
      ]
    },
    bouncing_ball: %{
      interval: 80,
      frames: [
	"( ●    )",
	"(  ●   )",
	"(   ●  )",
	"(    ● )",
	"(     ●)",
	"(    ● )",
	"(   ●  )",
	"(  ●   )",
	"( ●    )",
	"(●     )"
      ]
    },
    line: %{interval: 130, frames: ["-", "\\", "|", "/"]},
    simple_dots: %{interval: 400, frames: [".  ", ".. ", "...", "   "]},
    simple_dots_scrolling: %{interval: 200, frames: [".  ", ".. ", "...", " ..", "  .", "   "]},
    fancy_dots: %{interval: 80, frames: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]},
  }

  use GenServer

  defstruct [:color, :spinner, :text, :interval, :frame_count, :frame_index, :status, :output, :enabled]

  ## Public API

  def start(), do: start(GenServer.whereis(__MODULE__))
  def start(pid), do: GenServer.call(pid, :start, :infinity)

  def stop(), do: stop(GenServer.whereis(__MODULE__), "done!")
  def stop(status) when is_binary(status) do
    stop(GenServer.whereis(__MODULE__), status)
  end
  def stop(pid) when is_pid(pid), do: stop(pid, "done!")
  def stop(pid, status) when is_pid(pid) do
    ref = Process.monitor(pid)
    GenServer.cast(pid, {:stop, status})
    receive do
      {:DOWN, ^ref, _type, _pid, _reason} ->
        :ok
    end
  end

  def status(text), do: GenServer.cast(__MODULE__, {:status, text})
  def status(pid, text), do: GenServer.cast(pid, {:status, text})

  ## GenServer impl

  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil ->
        GenServer.start_link(__MODULE__, [opts], name: __MODULE__)
      name ->
        GenServer.start_link(__MODULE__, [opts], name: name)
    end
  end

  def init([opts]) do
    spinner = opt_spinner(opts)
    data = %__MODULE__{
      color: Keyword.get(opts, :color, :yellow),
      spinner: spinner,
      text: Keyword.get(opts, :text, "Loading..."),
      interval: Keyword.get(opts, :interval, spinner.interval || 100),
      frame_count: length(spinner.frames),
      frame_index: 0,
      enabled: enabled?(opts),
    }
    {:ok, data}
  end

  def handle_call(:start, _from, %{text: text, enabled: false} = data) do
    Artificery.Console.notice(text)
    {:reply, :ok, data}
  end
  def handle_call(:start, _from, %{interval: interval} = data) do
    # Subscribe to SIGWINCH
    Artificery.Console.Events.subscribe
    # Write out reset
    IO.write [@cursor_left, @erase_line, @cursor_hide]
    # Start spin timer
    Process.send_after(self(), :tick, interval)
    {:reply, :ok, data}
  end

  def handle_cast({:status, status}, %{text: text, enabled: false} = data) do
    Artificery.Console.notice(text <> " #{status}")
    {:noreply, Map.put(data, :status, status)}
  end
  def handle_cast({:status, status}, data) do
    data = render(set_status(data, status))
    {:noreply, render(set_status(data, status))}
  end
  def handle_cast({:stop, status}, %{text: text, enabled: false}) do
    Artificery.Console.notice(text <> " #{status}")
    {:stop, :normal, nil}
  end
  def handle_cast({:stop, status}, data) do
    Artificery.Console.Events.unsubscribe
    render(set_status(data, status))
    IO.write @cursor_show
    {:stop, :normal, nil}
  end

  def handle_info(:tick, %{interval: interval} = data) do
    Process.send_after(self(), :tick, interval)
    {:noreply, render(data)}
  end

  defp render(%{text: text, status: status} = data) do
    clear(data)
    {frame_data, data} = frame(data)
    output = "#{frame_data} #{text} #{status}\n"
    IO.write(output)
    %{data | output: output}
  end

  defp clear(%{output: output} = data) when is_nil(output) do
    data
  end
  defp clear(%{output: output} = data) do
    Artificery.Console.cursor_up(lines(output))
    IO.write @erase_down
    data
  end

  defp lines(s) do
    s
    |> ANSI.strip
    |> String.split("\n", trim: true)
    |> Enum.count
  end

  defp frame(%{spinner: %{frames: frames}, frame_count: max_frames, frame_index: frame_index} = data) do
    frame = Enum.at(frames, frame_index)
    frame = Artificery.Console.Color.style(frame, [data.color])
    if frame_index + 1 >= max_frames do
      {frame, %{data | frame_index: 0}}
    else
      {frame, %{data | frame_index: frame_index + 1}}
    end
  end

  defp set_status(data, nil), do: data
  defp set_status(data, status) do
    render(%{data | status: status})
  end

  defp opt_spinner(opts) do
    case :os.type() do
      {:win32, _} ->
        Map.get(@spinners, :line)
      _ ->
        case Map.get(@spinners, Keyword.get(opts, :spinner, :line)) do
          nil ->
            Map.get(@spinners, :dots2)
          s ->
            s
        end
    end
  end

  defp enabled?(opts) do
    supported? = Artificery.Console.Color.supports_color?
    stream = Keyword.get(opts, :stream, :standard_error)
    isatty? = stream in [:stdio, :standard_error]
    supported? and isatty?
  end
end
