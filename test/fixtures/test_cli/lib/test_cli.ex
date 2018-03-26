defmodule TestCli do
  @moduledoc false
  use Artificery

  defoption :key, :string, alias: :k

  option :verbose, :boolean, "Turn on verbose output"

  command :hello, "Say hello!" do
    argument :name, :string, "Name of person to greet"

    option :greeting, :string, "Set an alternate greeting", default: "Hello {name}!"
  end

  command :error, "Display an error"

  command :action, "Show a long running task" do
    option :spinner, :string, "The spinner to use", transform: &String.to_atom/1, default: :line

    command :subaction, [hidden: true], "Shouldn't be displayed"
  end

  command :hidden, "A hidden command" do
    option :thing, :string, hidden: true
  end

  command :keys, "Lists all stored key/value pairs" do
    option :file, :string, "The path of the stored data",
      default: "keys.tab",
      transform: &String.to_charlist/1

    command :set, [callback: :keyset], "Sets a key/value pair" do
      option :key, required: true
      option :value, :string, "The value to set", required: true
    end

    command :get, [callback: :keyget], "Gets the value for a key" do
      option :key, required: true
    end
  end

  command :ask, "Asks a question"

  def hello(_argv, %{name: name}) do
    Console.notice "Hello #{name}!"
  end

  def error(_argv, _opts) do
    Console.error "uh oh!"
  end

  def action(_argv, %{spinner: spinner}) do
    Console.spinner "Loading...", [spinner: spinner] do
      :timer.sleep(3_000)
    end
  end

  def ask(_argv, _opts) do
    is_phone_number = fn s -> 
      if String.match?(s, ~r/^[\d]{3}-[\d]{3}-[\d]{4}$/) do
        :ok
      else
        {:error, "Invalid phone number, must be in XXX-XXX-XXXX form!"}
      end
    end
    Console.Prompt.ask("What is your phone number", validator: is_phone_number)
  end

  def keys(_argv, %{file: file}) do
    path = List.to_string(file)
    Console.debug "Loading #{file}"
    case :ets.file2tab(file) do
      {:ok, tab} ->
        Console.debug "#{file} loaded successfully!"
        title = Path.basename(path)
        Console.Table.print(title, ["Key", "Value"], :ets.tab2list(tab))
      {:error, reason} ->
        Console.warn "File #{Path.relative_to_cwd(path)} doesn't exist: #{inspect reason}"
    end
  end

  def keyset(_argv, %{file: file, key: key, value: value}) do
    Console.debug "Loading #{file}"
    case :ets.file2tab(file) do
      {:ok, tab} ->
        Console.debug "#{file} loaded successfully!"
        :ets.insert(tab, {key, value})
        :ets.tab2file(tab, file)
        Console.success "#{key} was set to #{value}"
      {:error, reason} ->
        Console.error "Unable to load #{Path.relative_to_cwd(List.to_string(file))}: #{inspect reason}"
    end
  end

  def keyget(_argv, %{file: file, key: key}) do
    Console.debug "Loading #{file}"
    case :ets.file2tab(file) do
      {:ok, tab} ->
        Console.debug "#{file} loaded successfully!"
        case :ets.lookup(tab, key) do
          [] ->
            Console.warn "No entry for #{key}!"
          [{_key, value}] ->
            Console.success "#{inspect value}"
        end
      {:error, reason} ->
        Console.error "Unable to load #{Path.relative_to_cwd(List.to_string(file))}: #{inspect reason}"
    end
  end
end
