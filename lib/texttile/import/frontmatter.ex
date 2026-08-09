defmodule Texttile.Import.Frontmatter do
  @moduledoc """
  The front matter of a bundle's `index.md`: the restricted subset that
  IMPORT.md promises, nothing more. Scalars, inline lists and block
  lists, values optionally in double quotes. Parsing is strict on
  purpose; a converter that leaves the subset should hear it here, with
  a line number, not see its data half-read.
  """

  @key_pattern ~r/\A([a-z_][a-z0-9_]*):(.*)\z/

  @doc """
  Splits a document into its front matter and its body. Returns
  `{:ok, entries, body}` with entries as `%{key => value}`, a value
  being a string or a list of strings, or `{:error, message}`.
  """
  def parse(text) do
    case text |> to_string() |> String.split("\n") |> strip_cr_from_head() do
      ["---" | rest] ->
        case Enum.split_while(rest, &(String.trim_trailing(&1, "\r") != "---")) do
          {_block, []} ->
            {:error, "the front matter never closes: no second --- line"}

          {block, [_fence | body]} ->
            with {:ok, entries} <- read_block(block) do
              {:ok, entries, Enum.join(body, "\n")}
            end
        end

      _ ->
        {:error, "the file does not start with a --- line"}
    end
  end

  # Every other line is trimmed where it is read; the opening fence
  # gets the same treatment, so a CRLF file is not refused at line one.
  defp strip_cr_from_head([first | rest]), do: [String.trim_trailing(first, "\r") | rest]
  defp strip_cr_from_head([]), do: []

  # The block, line by line. `open` is the key of a block list that is
  # still collecting items, with the items gathered so far.
  defp read_block(lines) do
    lines
    |> Enum.with_index(2)
    |> Enum.reduce_while({%{}, nil}, fn {raw, number}, {entries, open} ->
      line = String.trim_trailing(raw, "\r")

      case classify(line) do
        :blank ->
          {:cont, {entries, open}}

        {:item, raw_value} ->
          case {open, scalar(raw_value)} do
            {nil, _} ->
              {:halt, {:error, "line #{number}: a list item without a list before it"}}

            {_, {:error, why}} ->
              {:halt, {:error, "line #{number}: #{why}"}}

            {{key, items}, {:ok, value}} ->
              {:cont, {entries, {key, items ++ [value]}}}
          end

        {:entry, key, raw_value} ->
          with {:ok, entries} <- close(entries, open),
               :ok <- fresh(entries, key, number),
               {:ok, value} <- value(raw_value, number) do
            case value do
              :block_list -> {:cont, {entries, {key, []}}}
              value -> {:cont, {Map.put(entries, key, value), nil}}
            end
          else
            {:error, message} -> {:halt, {:error, message}}
          end

        :other ->
          {:halt, {:error, "line #{number}: neither a key: value entry nor a list item"}}
      end
    end)
    |> case do
      {:error, message} -> {:error, message}
      {entries, open} -> close(entries, open)
    end
  end

  defp classify(""), do: :blank
  defp classify("  - " <> rest), do: {:item, rest}

  defp classify(line) do
    case Regex.run(@key_pattern, line) do
      [_, key, rest] -> {:entry, key, rest}
      nil -> :other
    end
  end

  defp close(entries, nil), do: {:ok, entries}

  defp close(_entries, {key, []}),
    do: {:error, "the key #{key} has no value and no list items"}

  defp close(entries, {key, items}), do: {:ok, Map.put(entries, key, items)}

  defp fresh(entries, key, number) do
    if Map.has_key?(entries, key) do
      {:error, "line #{number}: the key #{key} appears twice"}
    else
      :ok
    end
  end

  defp value(raw, number) do
    trimmed = String.trim(raw)

    result =
      cond do
        trimmed == "" -> {:ok, :block_list}
        String.starts_with?(trimmed, "[") -> inline_list(trimmed)
        true -> scalar(trimmed)
      end

    with {:error, why} <- result, do: {:error, "line #{number}: #{why}"}
  end

  @doc """
  One value: quoted with `\\"` and `\\\\` escapes, or the verbatim
  text. The comments of a bundle quote their fields the same way, so
  the rule lives here for both.
  """
  def scalar(raw) do
    trimmed = String.trim(raw)

    case trimmed do
      "\"" <> rest ->
        with {:ok, value, tail} <- read_quoted(rest, "") do
          if String.trim(tail) == "" do
            {:ok, value}
          else
            {:error, "text after the closing quote: #{tail}"}
          end
        end

      _ ->
        {:ok, trimmed}
    end
  end

  defp read_quoted("", _acc), do: {:error, "the quote never closes"}
  defp read_quoted("\\\"" <> rest, acc), do: read_quoted(rest, acc <> "\"")
  defp read_quoted("\\\\" <> rest, acc), do: read_quoted(rest, acc <> "\\")
  defp read_quoted("\\" <> _rest, _acc), do: {:error, "only \\\" and \\\\ are escapes"}
  defp read_quoted("\"" <> rest, acc), do: {:ok, acc, rest}

  defp read_quoted(<<char::utf8, rest::binary>>, acc),
    do: read_quoted(rest, acc <> <<char::utf8>>)

  defp inline_list(trimmed) do
    if String.ends_with?(trimmed, "]") do
      inner = trimmed |> String.slice(1..-2//1) |> String.trim()

      if inner == "" do
        {:ok, []}
      else
        read_items(inner, [])
      end
    else
      {:error, "an inline list must end with ]"}
    end
  end

  defp read_items(rest, acc) do
    rest = String.trim_leading(rest)

    with {:ok, value, tail} <- read_item(rest) do
      case String.trim_leading(tail) do
        "" -> {:ok, Enum.reverse([value | acc])}
        "," <> more -> read_items(more, [value | acc])
        other -> {:error, "expected a comma before: #{other}"}
      end
    end
  end

  defp read_item("\"" <> rest), do: read_quoted(rest, "")

  defp read_item(rest) do
    {value, tail} =
      case String.split(rest, ",", parts: 2) do
        [value] -> {value, ""}
        [value, tail] -> {value, "," <> tail}
      end

    {:ok, String.trim(value), tail}
  end
end
