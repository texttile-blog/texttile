defmodule Texttile.Articles.Diff do
  @moduledoc "Word differences that preserve the original whitespace."

  @word_diff_cap 500_000

  @doc """
  The word-level diff between two texts, as a flat list of
  `{:same | :add | :del, token}` runs in reading order. Tokens are
  words and the whitespace between them, so joining the `:same` and
  `:add` tokens gives back the new text byte for byte.

  The untouched head and tail of the text are peeled off before the
  LCS runs, so a long article with a small edit still gets a real
  diff; only a rewrite of half a book falls back to "all new".
  """
  def between(old_text, new_text) do
    a = tokenize(old_text)
    b = tokenize(new_text)

    {head, a, b, tail} = peel(a, b)

    n = length(a)
    m = length(b)

    middle =
      cond do
        n == 0 and m == 0 -> []
        n * m > @word_diff_cap -> Enum.map(a, &{:del, &1}) ++ Enum.map(b, &{:add, &1})
        true -> walk(List.to_tuple(a), List.to_tuple(b), lcs_table(a, b, m))
      end

    Enum.map(head, &{:same, &1}) ++ middle ++ Enum.map(tail, &{:same, &1})
  end

  # The common head and tail, token by token: {head, a_rest, b_rest, tail}.
  defp peel(a, b) do
    {head, a, b} = peel_head(a, b, [])
    {a_rev, b_rev} = {Enum.reverse(a), Enum.reverse(b)}
    {tail_rev, a_rev, b_rev} = peel_head(a_rev, b_rev, [])
    {Enum.reverse(head), Enum.reverse(a_rev), Enum.reverse(b_rev), tail_rev}
  end

  defp peel_head([x | a], [x | b], acc), do: peel_head(a, b, [x | acc])
  defp peel_head(a, b, acc), do: {acc, a, b}

  defp tokenize(text) do
    text
    |> to_string()
    |> String.split(~r/(?<=\s)(?=\S)|(?<=\S)(?=\s)/)
    |> Enum.reject(&(&1 == ""))
  end

  # The classic LCS table, built bottom-up: row i holds, for every j,
  # the length of the longest common run of a[i..] and b[j..].
  defp lcs_table(a, b, m) do
    b_tuple = List.to_tuple(b)
    empty = Tuple.duplicate(0, m + 1)

    a
    |> Enum.reverse()
    |> Enum.reduce([empty], fn token, [below | _] = rows ->
      row =
        Enum.reduce((m - 1)..0//-1, [elem(empty, 0)], fn j, [right | _] = acc ->
          cell =
            if token == elem(b_tuple, j) do
              elem(below, j + 1) + 1
            else
              max(elem(below, j), right)
            end

          [cell | acc]
        end)

      [List.to_tuple(row) | rows]
    end)
    |> List.to_tuple()
  end

  defp walk(a, b, table), do: walk(a, b, table, 0, 0, [])

  defp walk(a, b, table, i, j, acc) do
    n = tuple_size(a)
    m = tuple_size(b)

    cond do
      i < n and j < m and elem(a, i) == elem(b, j) ->
        walk(a, b, table, i + 1, j + 1, [{:same, elem(a, i)} | acc])

      i < n and (j == m or elem(elem(table, i + 1), j) >= elem(elem(table, i), j + 1)) ->
        walk(a, b, table, i + 1, j, [{:del, elem(a, i)} | acc])

      j < m ->
        walk(a, b, table, i, j + 1, [{:add, elem(b, j)} | acc])

      true ->
        Enum.reverse(acc)
    end
  end
end
