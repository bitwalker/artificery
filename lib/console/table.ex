defmodule Artificery.Console.Table do
  @moduledoc "A printer for tabular data"

  @doc """
  Given a title, header, and rows, prints the data as a table.

  Takes the same options as `format/4`.
  """
  def print(title, header, rows, opts \\ []) do
    IO.write(format(title, header, rows, opts))
  end

  @doc """
  Given a title, header, and rows, formats the data as a table.

  Takes an optional keyword list of options:

  - `padding: integer` sets the padding around columns

  This function formats the data as iodata, it is up to the caller to print it
  """
  def format(title, header, rows, opts \\ []) do
    padding = Keyword.get(opts, :padding, 1)
    header = [header]
    rows = stringify(rows)
    widths = rows |> transpose() |> column_widths()

    widths =
      header
      |> transpose()
      |> column_widths()
      |> Enum.with_index()
      |> Enum.map(fn {c, i} -> max(c, Enum.at(widths, i)) end)

    head =
      header
      |> pad_cells(widths, padding)
      |> Enum.map(&[&1, ?\n])

    head_len =
      head
      |> IO.iodata_to_binary()
      |> String.length()

    separator = [String.duplicate("-", head_len)]

    tail =
      rows
      |> pad_cells(widths, padding)
      |> Enum.map(&[&1, ?\n, separator, ?\n])

    [IO.ANSI.bright(), title, IO.ANSI.reset(), ?\n, ?\n, head, separator, ?\n, tail]
  end

  defp stringify(rows, acc \\ [])
  defp stringify([], acc), do: Enum.reverse(acc)
  defp stringify([row | rest], acc), do: stringify(rest, [Enum.map(row, &to_string/1) | acc])

  defp transpose(rows), do: rows |> List.zip() |> Enum.map(&Tuple.to_list/1)

  defp column_widths(cols) do
    Enum.map(cols, fn c -> c |> Enum.map(&byte_size/1) |> Enum.max() end)
  end

  defp pad_cells(rows, widths, padding) do
    for r <- rows do
      last_i = length(r) - 1

      for {{val, width}, i} <- r |> Enum.zip(widths) |> Enum.with_index() do
        if i == last_i do
          # Don't pad last col
          val
        else
          calculated_padding = max(width - byte_size(val) + padding, padding)
          [val, String.pad_leading("", calculated_padding), ?|, ?\s]
        end
      end
    end
  end
end
