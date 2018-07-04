defmodule Artificery.Console.Prompt do
  @moduledoc false
  alias Artificery.Console
  alias Artificery.Console.Color

  @type validator :: (String.t -> :ok | {:error, String.t})
  @type transform :: (String.t -> term)

  @type ask_option :: {:default, term}
                    | {:validator, validator}
                    | {:transform, transform}
  @type ask_options :: [ask_option]

  @spec yes?(String.t) :: boolean
  def yes?(question) when is_binary(question) do
    prompt = Color.style("? ", [:green]) <> question <> " (Y/n) "
    reply = IO.gets(prompt)
    is_binary(reply) and String.trim(reply) in ["", "y", "Y", "yes", "Yes", "YES"]
  end

  @spec ask(String.t) :: term
  @spec ask(String.t, ask_options) :: term
  def ask(question, opts \\ []) do
    validator = Keyword.get(opts, :validator)
    transform = Keyword.get(opts, :transform)
    default = Keyword.get(opts, :default)
    # TODO: Provide mechanism for inputting secrets
    # masked? = Keyword.get(opts, :masked, false)

    # Ask question
    prompt = Color.style("? ", [:green]) <> question <> ": " <> IO.ANSI.cyan
    answer = IO.gets(prompt)
    # Reset color
    IO.write IO.ANSI.reset

    # Validate answer
    validation =
      if is_function(validator, 1) do
        validator.(answer)
      else
        :ok
      end

    case answer do
      "" when validation == :ok ->
        default
      s when is_binary(s) and validation == :ok ->
        if is_function(transform, 1) do
          transform.(s)
        else
          s
        end
      _ ->
        # Invalid
        {:error, message} = validation
        # Clear current line
        Console.erase_line
        # Write validation error
        Console.write(">>> #{message}", [:red])
        # Go back to question line and erase it
        Console.cursor_prev_line
        Console.erase_line
        # Ask the question again
        ask(question, opts)
    end
  end

  # TODO: Open EDITOR to a temp file, read in result when closed
  @doc false
  @spec edit() :: String.t
  def edit(), do: exit(:not_implemented)

  # TODO: Choose from a selection of options
  @doc false
  @spec choose(String.t, [String.t]) :: String.t
  def choose(question, choices) when is_binary(question) and is_list(choices) do
    exit(:not_implemented)
  end
end
