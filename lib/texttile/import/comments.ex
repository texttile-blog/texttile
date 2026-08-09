defmodule Texttile.Import.Comments do
  @moduledoc """
  The `comments.yaml` of one bundle: the restricted subset IMPORT.md
  promises, read into the comments of the entry. A list of comments,
  each a few single-line fields and one text, the text either on its
  line or in a `|` block indented with four spaces.

  Reading answers the comments in the order they will stand under the
  entry - oldest first, and a reply right behind the comment it
  answers, because the comments here are one row of words after
  another and `reply_to` has nowhere else to go. Everything wrong with
  the file comes back beside them, so the dry run says it all at once
  and the run never trips over a broken file.
  """

  alias Texttile.Comments.Comment
  alias Texttile.Confirmation
  alias Texttile.Import.Frontmatter

  @name "comments.yaml"
  @fields ~w(author email website date id reply_to text)
  @key_pattern ~r/\A([a-z_][a-z0-9_]*):(.*)\z/
  @name_limit 120

  @doc "The name of the file a bundle carries its comments in."
  def filename, do: @name

  @doc """
  Reads the `comments.yaml` of the bundle folder `dir`. Answers
  `{comments, errors}`: the comments in reading order, or none at all
  when something is wrong, and every complaint about the file. A
  bundle without the file has neither.
  """
  def read(dir) do
    case File.read(Path.join(dir, @name)) do
      {:error, _} -> {[], []}
      {:ok, text} -> parse(text)
    end
  end

  defp parse(text) do
    with {:ok, items} <- items(text),
         {:ok, comments} <- typed(items),
         {:ok, comments} <- linked(comments) do
      {threaded(comments), []}
    else
      {:error, messages} -> {[], messages}
    end
  end

  ## The lines

  # The file, line by line. The state is the comments read so far, the
  # one being collected, and the `|` block still taking lines.
  defp items(source) do
    source
    |> to_string()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while({[], nil, nil}, fn {raw, number}, state ->
      case line(String.trim_trailing(raw, "\r"), number, state) do
        {:error, _messages} = error -> {:halt, error}
        state -> {:cont, state}
      end
    end)
    |> case do
      {:error, _messages} = error -> error
      state -> close_item(state)
    end
  end

  # A line of a `|` block: four spaces and whatever stands under them,
  # an empty line included. Anything less indented ends the block, and
  # the line is then read as what it is.
  defp line(raw, number, {items, current, text}) when is_list(text) do
    if raw == "" or String.starts_with?(raw, "    ") do
      {items, current, [String.replace_prefix(raw, "    ", "") | text]}
    else
      with {:ok, current} <- put_text(current, text) do
        line(raw, number, {items, current, nil})
      end
    end
  end

  defp line("", _number, state), do: state

  defp line("- " <> rest, number, {items, current, nil}) do
    field(%{fields: %{}, line: number}, rest, number, close(items, current))
  end

  defp line("  " <> rest, number, {items, current, nil}) do
    cond do
      String.starts_with?(rest, " ") ->
        {:error, [complaint(number, "a field takes two spaces, not more")]}

      current == nil ->
        {:error, [complaint(number, "a field before the first comment")]}

      true ->
        field(current, rest, number, items)
    end
  end

  defp line(_raw, number, _state) do
    {:error, [complaint(number, "neither a comment nor a field")]}
  end

  # One `key: value` of the comment being collected. A `|` value opens
  # the text block; every other value is one scalar, quoted the way the
  # front matter quotes.
  defp field(current, raw, number, items) do
    case Regex.run(@key_pattern, raw) do
      nil ->
        {:error, [complaint(number, "neither a comment nor a field")]}

      [_, key, rest] ->
        cond do
          key not in @fields ->
            {:error, [complaint(number, "the field #{key} is not part of the format")]}

          Map.has_key?(current.fields, key) ->
            {:error, [complaint(number, "the field #{key} appears twice in one comment")]}

          key == "text" and String.trim(rest) == "|" ->
            {items, current, []}

          String.trim(rest) == "" ->
            {:error, [complaint(number, "the field #{key} has no value")]}

          true ->
            case Frontmatter.scalar(rest) do
              {:ok, value} -> {items, put_field(current, key, value), nil}
              {:error, why} -> {:error, [complaint(number, why)]}
            end
        end
    end
  end

  defp put_field(current, key, value) do
    %{current | fields: Map.put(current.fields, key, value)}
  end

  # The gathered block becomes the text: the lines as they were
  # written, without the empty ones the block collected on its way to
  # the next comment.
  defp put_text(nil, _text), do: {:error, [complaint(nil, "a text before the first comment")]}

  defp put_text(current, text) do
    words =
      text
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.join("\n")

    {:ok, put_field(current, "text", words)}
  end

  defp close(items, nil), do: items
  defp close(items, current), do: [current | items]

  defp close_item({items, current, nil}), do: {:ok, Enum.reverse(close(items, current))}

  defp close_item({items, current, text}) do
    with {:ok, current} <- put_text(current, text) do
      close_item({items, current, nil})
    end
  end

  ## The values

  # Every comment of the file, typed and judged. One broken comment
  # does not hide the next: the whole file answers at once.
  defp typed(items) do
    {comments, errors} =
      Enum.reduce(items, {[], []}, fn item, {comments, errors} ->
        case comment(item) do
          {:ok, comment} -> {[comment | comments], errors}
          {:error, messages} -> {comments, errors ++ messages}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(comments)}, else: {:error, errors}
  end

  defp comment(%{fields: fields, line: line}) do
    readers = [
      {:author, "author", &author/1},
      {:text, "text", &text/1},
      {:at, "date", &at/1},
      {:email, "email", &email/1},
      {:website, "website", &website/1},
      {:id, "id", &number(&1, "id")},
      {:reply_to, "reply_to", &number(&1, "reply_to")}
    ]

    {values, errors} =
      Enum.reduce(readers, {%{line: line}, []}, fn {key, name, read}, {values, errors} ->
        case read.(Map.get(fields, name)) do
          {:ok, value} -> {Map.put(values, key, value), errors}
          {:error, why} -> {values, errors ++ [complaint(line, why)]}
        end
      end)

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  defp author(nil), do: {:error, "the comment has no author"}

  defp author(value) do
    name = String.trim(value)

    cond do
      name == "" -> {:error, "the comment has no author"}
      String.length(name) > @name_limit -> {:error, "the author is longer than 120 characters"}
      true -> {:ok, name}
    end
  end

  defp text(nil), do: {:error, "the comment has no text"}

  defp text(value) do
    words = String.trim(value)

    cond do
      words == "" ->
        {:error, "the comment has no text"}

      String.length(words) > Comment.body_limit() ->
        {:error, "the text is longer than #{Comment.body_limit()} characters"}

      true ->
        {:ok, words}
    end
  end

  defp at(nil), do: {:error, "the comment has no date"}

  defp at(value) do
    stamp = String.trim(value)

    with_seconds =
      if Regex.match?(~r/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}\z/, stamp),
        do: stamp <> ":00",
        else: stamp

    case NaiveDateTime.from_iso8601(with_seconds) do
      {:ok, naive} ->
        {:ok, naive |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC")}

      {:error, _reason} ->
        {:error, "the date is YYYY-MM-DD HH:MM, seconds allowed, not #{value}"}
    end
  end

  defp email(nil), do: {:ok, nil}

  defp email(value) do
    address = Confirmation.normalize(value)

    cond do
      address == "" -> {:ok, nil}
      Confirmation.address?(address) -> {:ok, address}
      true -> {:error, "the email #{value} is not an address"}
    end
  end

  defp website(nil), do: {:ok, nil}

  defp website(value) do
    address = String.trim(value)

    cond do
      address == "" -> {:ok, nil}
      String.starts_with?(address, ["http://", "https://"]) -> {:ok, address}
      true -> {:error, "the website #{value} is neither http nor https"}
    end
  end

  defp number(nil, _key), do: {:ok, nil}

  defp number(value, key) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "#{key} takes a number, not #{value}"}
    end
  end

  ## The threads

  # `id` names a comment, `reply_to` points at one. Both have to hold
  # before the order can follow them.
  defp linked(comments) do
    ids = comments |> Enum.map(& &1.id) |> Enum.reject(&is_nil/1)
    known = MapSet.new(ids)

    taken =
      ids |> Enum.frequencies() |> Enum.filter(&(elem(&1, 1) > 1)) |> Enum.map(&elem(&1, 0))

    errors =
      Enum.map(Enum.sort(taken), &"#{prefix()}the id #{&1} belongs to more than one comment") ++
        Enum.flat_map(comments, fn comment -> answers(comment, known) end)

    cond do
      errors != [] -> {:error, errors}
      circles?(comments) -> {:error, [prefix() <> "the replies answer each other in a circle"]}
      true -> {:ok, comments}
    end
  end

  defp answers(%{reply_to: nil}, _known), do: []

  defp answers(comment, known) do
    cond do
      comment.reply_to == comment.id ->
        [complaint(comment.line, "the comment answers itself")]

      not MapSet.member?(known, comment.reply_to) ->
        [complaint(comment.line, "reply_to #{comment.reply_to} names no comment of the file")]

      true ->
        []
    end
  end

  # Walking up from every comment has to reach one that answers
  # nothing. A walk longer than the file itself has gone round.
  defp circles?(comments) do
    parents = Map.new(comments, &{&1.id, &1.reply_to})
    Enum.any?(comments, &circle?(&1.reply_to, parents, map_size(parents)))
  end

  defp circle?(nil, _parents, _left), do: false
  defp circle?(_id, _parents, 0), do: true
  defp circle?(id, parents, left), do: circle?(Map.get(parents, id), parents, left - 1)

  # The reading order: oldest first, and every reply right behind the
  # comment it answers, its own replies behind it.
  defp threaded(comments) do
    comments
    |> Enum.sort_by(&{DateTime.to_unix(&1.at), &1.line})
    |> Enum.group_by(& &1.reply_to)
    |> behind(nil)
  end

  defp behind(by_parent, id) do
    by_parent
    |> Map.get(id, [])
    |> Enum.flat_map(fn comment ->
      [comment | if(comment.id, do: behind(by_parent, comment.id), else: [])]
    end)
  end

  defp complaint(nil, why), do: prefix() <> why
  defp complaint(number, why), do: "#{prefix()}line #{number}: #{why}"
  defp prefix, do: "#{@name}: "
end
