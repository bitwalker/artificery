defmodule Artificery.Console.Events do
  @moduledoc false

  @behaviour :gen_event

  @doc """
  Start listening for console events
  """
  def start do
    :gen_event.add_handler(:erl_signal_server, __MODULE__, [])
  end

  @doc """
  Stop listening for console events
  """
  def stop do
    :gen_event.delete_handler(:erl_signal_server, __MODULE__, :normal)
  end

  @doc """
  Subscribe the current process to event notifications
  """
  def subscribe do
    :gen_event.call(:erl_signal_server, __MODULE__, {:subscribe, self()})
  end

  @doc """
  Unsubscribe the current process from event notifications
  """
  def unsubscribe do
    :gen_event.call(:erl_signal_server, __MODULE__, {:unsubscribe, self()})
  end

  ## gen_event implementation

  @impl :gen_event
  def init(_args), do: {:ok, %{}}

  @impl :gen_event
  def handle_event(:sigwinch, subscribers) do
    # SIGWINCH: Window size change. This is generated on some systems (including GNU)
    # when the terminal driver's record of the number of rows and columns on the screen
    # is changed. The default action is to ignore it.
    # If a program does full-screen display, it should handle SIGWINCH. When the signal
    # arrives, it should fetch the new screen size and reformat its display accordingly.
    notify(subscribers, :sigwinch)
    {:ok, subscribers}
  end
  def handle_event(_, subscribers), do: {:ok, subscribers}

  @impl :gen_event
  def handle_call({:subscribe, pid}, subscribers) do
    if Map.get(subscribers, pid) do
      {:ok, :ok, subscribers}
    else
      ref = Process.monitor(pid)
      {:ok, :ok, Map.put(subscribers, pid, ref)}
    end
  end
  def handle_call({:unsubscribe, pid}, subscribers) do
    case Map.get(subscribers, pid) do
      nil ->
        {:ok, :ok, subscribers}
      ref ->
        Process.demonitor(ref, [:flush])
        {:ok, :ok, Map.delete(subscribers, pid)}
    end
  end

  @impl :gen_event
  def handle_info({:DOWN, _ref, _type, pid, _reason}, subscribers) do
    {:noreply, Map.delete(subscribers, pid)}
  end

  @impl :gen_event
  def format_status(_opt, [_pdict, _s]), do: :ok

  @impl :gen_event
  def code_change(_old_vsn, subscribers, _extra), do: {:ok, subscribers}

  @impl :gen_event
  def terminate(_args, _subscribers), do: :ok

  ## Private

  defp notify(subscribers, event) do
    for {pid, _} <- subscribers do
      send(pid, {:event, event})
    end
  end
end
