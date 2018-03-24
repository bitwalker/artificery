defmodule Artificery.Console.Color do
  @moduledoc false

  defmodule ANSI do
    @moduledoc false

    require IO.ANSI.Sequence
    import IO.ANSI.Sequence

    defsequence :grey, 37

    @ansi_pattern Enum.join([
        "[\\e\\x{c29B}][[\\]()#;?]*(?:(?:(?:[a-zA-Z\\d]*(?:;[a-zA-Z\\d]*)*)?\\a)",
        "(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PRZcf-ntqry=><~]))"
      ], "|") |> Regex.compile!("u")

    def strip(text) when is_binary(text) do
      String.replace(text, @ansi_pattern, "")
    end
  end

  @doc """
  Applies one or more styles to the given binary, styles can include
  any of those found in `IO.ANSI`, such as `:faint` or `:cyan`, and also
  supports `:dim` as an alias for `:faint`, as well as `:grey` or `:gray`.

  Returns a formatted binary
  """
  @spec style(binary, [atom]) :: binary
  def style(msg, styles) when is_list(styles) do
    do_style(Enum.uniq(styles), [msg], false)
  end

  defp do_style([], acc, _grey), do: IO.iodata_to_binary([acc, IO.ANSI.reset])
  defp do_style([:dim], acc, true) do
    # Ignore dimming to prevent text disappearing on Windows
    acc
  end
  defp do_style([:dim], acc, false) do
    [IO.ANSI.faint | acc]
  end
  defp do_style([:dim | styles], acc, grey?) do
    # Apply dimming last to be sure there is no grey
    do_style(styles ++ [:dim], acc, grey?)
  end
  defp do_style([grey | styles], acc, _grey?) when grey in [:gray, :grey] do
    do_style(styles, [ANSI.grey | acc], true)
  end
  defp do_style([style | styles], acc, grey?) do
    do_style(styles, [apply(IO.ANSI, style, []) | acc], grey?)
  end

  @doc """
  Returns true if the current terminal supports color output, false if not
  """
  @spec supports_color?() :: boolean
  def supports_color? do
    supports() != :nocolor
  end

  @doc """
  Returns true if the current terminal supports 256bit color output, false if not
  """
  @spec supports_256color?() :: boolean
  def supports_256color? do
    supports() in [:color256, :color16m]
  end

  @doc """
  Returns true if the current terminal supports 16M bit color output, false if not
  """
  @spec supports_truecolor?() :: boolean
  def supports_truecolor? do
    supports() == :color16m
  end

  # Returns what level of color support the current TTY has
  @spec supports() :: :nocolor | :color | :color256 | :color16m
  defp supports do
    min =
      if IO.ANSI.enabled? do
        :color
      else
        :nocolor
      end

    case :os.type() do
      {:win32, _} ->
        case :os.version() do
          {10, _, build} when build >= 14931 ->
            throw :color16m

          {10, _, build} when build >= 10586 ->
            throw :color256

          {_, _, _} ->
            throw :color
        end

      _ ->
        :ok
    end

    if System.get_env("CI") do
      cond do
        System.get_env("TRAVIS") ->
          throw :color
        System.get_env("CIRCLECI") ->
          throw :color
        System.get_env("GITLAB_CI") ->
          throw :color
        :else ->
          throw :nocolor
      end
    end

    if System.get_env("COLORTERM") == "truecolor" do
      throw :color16m
    end

    if System.get_env("TERM_PROGRAM") do
      case System.get_env("TERM_PROGRAM") do
        "iTerm.app" ->
          {:ok, min_version} = Version.parse("3.0.0")
          case Version.parse(System.get_env("TERM_PROGRAM_VERSION")) do
            {:ok, term_version} ->
              if Version.compare(term_version, min_version) in [:gt, :eq] do
                throw :color16m
              else
                throw :color256
              end

            _ ->
              :ok
          end

        "Apple_Terminal" ->
          throw :color256
      end
    end

    if String.match?(System.get_env("TERM"), ~r/-256(color)?$/i) do
      throw :color256
    end

    if String.match?(System.get_env("TERM"), ~r/^screen|^xterm|^vt100|^rxvt|color|ansi|cygwin|linux/i) do
      throw :color
    end

    if System.get_env("COLORTERM") do
      throw :color
    end

    if System.get_env("TERM") == "dumb" do
      min
    end

    min

  catch
    :throw, supported_level ->
      supported_level
  end
end
