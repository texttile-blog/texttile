defmodule Texttile.Articles do
  @moduledoc """
  The texts: drafts, scheduled texts and published ones, their versions
  and their Log.

  The concurrency model, from the collaboration spec: the title and the
  body belong to one admin at a time (see `Texttile.Articles.Lock`);
  everything else is freely editable by every admin all the time, last
  write wins per field. Every accepted change is announced, on the desk
  topic for the grid and on the article's own topic for open editors.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
  alias Texttile.Articles.LogEntry
  alias Texttile.Articles.Version
  alias Texttile.Repo

  @desk_topic "articles"

  ## PubSub

  def subscribe_desk do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @desk_topic)
  end

  def subscribe(article_id) do
    Phoenix.PubSub.subscribe(Texttile.PubSub, topic(article_id))
  end

  defp topic(article_id), do: "article:#{article_id}"

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @desk_topic, message)

    case message do
      {_, %Article{id: id}} -> Phoenix.PubSub.broadcast(Texttile.PubSub, topic(id), message)
      {_, id} when is_integer(id) -> Phoenix.PubSub.broadcast(Texttile.PubSub, topic(id), message)
      _ -> :ok
    end
  end

  ## Reading

  def get_article!(id), do: Repo.get!(Article, id)

  @doc """
  The texts for the grid, newest work first. `filter:` narrows to one
  status ("all" and nil mean everything), `search:` looks through the
  title, the tags and the body, case-insensitively.
  """
  def list_articles(opts \\ []) do
    filter = opts[:filter]
    search = opts[:search] |> to_string() |> String.trim()

    Article
    |> then(fn q ->
      if filter in [nil, "all"], do: q, else: where(q, [a], a.status == ^filter)
    end)
    |> then(fn q ->
      if search == "" do
        q
      else
        like = "%#{String.downcase(search)}%"

        where(
          q,
          [a],
          like(fragment("lower(?)", a.title), ^like) or
            like(fragment("lower(?)", a.tags), ^like) or
            like(fragment("lower(?)", a.body), ^like)
        )
      end
    end)
    |> order_by([a], desc: a.updated_at, desc: a.id)
    |> Repo.all()
  end

  ## Writing

  @doc "A new, empty draft, and the first line of its Log."
  def create_draft(user) do
    {:ok, article} = Repo.insert(%Article{})
    push_log(article, user, "started the text")
    broadcast({:article_changed, article})
    {:ok, article}
  end

  @doc """
  The autosave: writes the title and the body into the working state.
  No log line and no version; typing is not an event.
  """
  def update_text(%Article{} = article, attrs) do
    with {:ok, article} <- article |> Article.text_changeset(attrs) |> Repo.update() do
      broadcast({:text_changed, article})
      {:ok, article}
    end
  end

  @doc "One article setting changed. Atomic, last write wins."
  def update_settings(%Article{} = article, attrs) do
    with {:ok, article} <- article |> Article.settings_changeset(attrs) |> Repo.update() do
      broadcast({:article_changed, article})
      {:ok, article}
    end
  end

  @doc """
  The one publish click. An empty or past date goes live today, a
  future date schedules; `force: true` (the "Publish now" of a
  scheduled text) goes live today regardless. Publishing writes a
  version snapshot, so "this is how it went live" is always restorable.
  """
  def publish(%Article{} = article, user, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    day = if opts[:force], do: today, else: article.publish_date || today
    future? = Date.compare(day, today) == :gt
    status = if future?, do: "scheduled", else: "published"

    attrs = %{status: status, publish_date: day, slug: article.slug || free_slug(article)}

    with {:ok, article} <- article |> Article.state_changeset(attrs) |> Repo.update() do
      snapshot(article, user)

      push_log(
        article,
        user,
        if(future?, do: "scheduled the text for #{day}", else: "published the text")
      )

      broadcast({:article_changed, article})
      {:ok, article}
    end
  end

  @doc "The undo of both states: back to a draft, the date cleared."
  def unpublish(%Article{} = article, user) do
    was = article.status

    with {:ok, article} <-
           article
           |> Article.state_changeset(%{status: "draft", publish_date: nil})
           |> Repo.update() do
      push_log(
        article,
        user,
        if(was == "scheduled", do: "unscheduled the text", else: "unpublished the text")
      )

      broadcast({:article_changed, article})
      {:ok, article}
    end
  end

  @doc """
  The publish date changed in the settings. A draft keeps the date for
  later. On a live text the date is the state: a future day schedules,
  a past or present day publishes, and clearing it is the same
  statement as Unpublish, so it does the same thing.
  """
  def set_publish_date(%Article{} = article, user, date, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    cond do
      article.status != "draft" and is_nil(date) ->
        unpublish(article, user)

      article.status == "draft" ->
        with {:ok, article} <-
               article |> Article.state_changeset(%{publish_date: date}) |> Repo.update() do
          broadcast({:article_changed, article})
          {:ok, article}
        end

      true ->
        status = if Date.compare(date, today) == :gt, do: "scheduled", else: "published"

        with {:ok, article} <-
               article
               |> Article.state_changeset(%{publish_date: date, status: status})
               |> Repo.update() do
          broadcast({:article_changed, article})
          {:ok, article}
        end
    end
  end

  @doc """
  Scheduled texts whose day has come go live. Returns the texts that
  went live, for the caller to act on (the subscriber email, once the
  newsletter exists, goes out here and only here).
  """
  def go_live_due(today \\ Date.utc_today()) do
    Article
    |> where([a], a.status == "scheduled" and a.publish_date <= ^today)
    |> Repo.all()
    |> Enum.map(fn article ->
      {:ok, article} = article |> Article.state_changeset(%{status: "published"}) |> Repo.update()
      push_log(article, nil, "the text went live as scheduled")
      broadcast({:article_changed, article})
      article
    end)
  end

  @doc "Deletes the text and everything that hangs on it."
  def delete_article(%Article{} = article) do
    with {:ok, article} <- Repo.delete(article) do
      broadcast({:article_deleted, article.id})
      {:ok, article}
    end
  end

  ## Versions

  @doc "The versions of a text, newest first, with their authors."
  def versions(%Article{id: id}) do
    Version
    |> where([v], v.article_id == ^id)
    |> order_by([v], desc: v.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Save version: a snapshot of the title and the body as they stand.
  Byte-identical to the newest version means nothing to keep.
  """
  def save_version(%Article{} = article, user) do
    case snapshot(article, user) do
      {:ok, version} ->
        push_log(article, user, "saved a version of the text")
        broadcast({:versions_changed, article.id})
        {:ok, version}

      :unchanged ->
        :unchanged
    end
  end

  @doc """
  A snapshot without the log line: the automatic versions (on publish,
  on handover) use this. Deduplicates against the newest version.
  """
  def snapshot(%Article{} = article, user) do
    newest =
      Version
      |> where([v], v.article_id == ^article.id)
      |> order_by([v], desc: v.id)
      |> limit(1)
      |> Repo.one()

    if newest && newest.title == article.title && newest.body == article.body do
      :unchanged
    else
      version =
        Repo.insert!(%Version{
          article_id: article.id,
          title: article.title,
          body: article.body,
          user_id: user && user.id
        })

      broadcast({:versions_changed, article.id})
      {:ok, version}
    end
  end

  @doc """
  Restore: the version's title and body become the working state. The
  pre-restore state is snapshotted first, so a restore is always
  undoable. Status, slug, date and settings stay untouched; restoring
  content never takes a published text offline.
  """
  def restore_version(%Article{} = article, %Version{} = version, user) do
    snapshot(article, user)

    with {:ok, article} <-
           article
           |> Article.text_changeset(%{title: version.title, body: version.body})
           |> Repo.update() do
      push_log(article, user, "restored the version from #{stamp(version.inserted_at)}")
      broadcast({:text_changed, article})
      broadcast({:versions_changed, article.id})
      {:ok, article}
    end
  end

  defp stamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  ## Log

  @doc "The Log of a text, newest first, with the people preloaded."
  def log(%Article{id: id}) do
    LogEntry
    |> where([l], l.article_id == ^id)
    |> order_by([l], desc: l.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "One line into the Log. `user` may be nil for the system."
  def push_log(%Article{} = article, user, text) do
    entry =
      Repo.insert!(%LogEntry{article_id: article.id, user_id: user && user.id, text: text})

    broadcast({:log_changed, article.id})
    entry
  end

  ## Slugs

  @doc "A title turned into an address: lowercase, dashes, nothing else."
  def slugify(title) do
    title
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp free_slug(%Article{} = article) do
    base =
      case slugify(article.title) do
        "" -> "untitled"
        slug -> slug
      end

    taken =
      Article
      |> where([a], like(a.slug, ^"#{base}%") and a.id != ^article.id)
      |> select([a], a.slug)
      |> Repo.all()
      |> MapSet.new()

    if base in taken do
      Enum.find(Stream.map(2..1000, &"#{base}-#{&1}"), &(&1 not in taken))
    else
      base
    end
  end

  ## Diff

  @word_diff_cap 500_000

  @doc """
  The word-level diff between two texts, as a flat list of
  `{:same | :add | :del, token}` runs in reading order. Tokens are
  words and the whitespace between them, so joining the `:same` and
  `:add` tokens gives back the new text byte for byte.
  """
  def diff(old_text, new_text) do
    a = tokenize(old_text)
    b = tokenize(new_text)
    n = length(a)
    m = length(b)

    if n * m > @word_diff_cap do
      [{:add, to_string(new_text)}]
    else
      walk(List.to_tuple(a), List.to_tuple(b), lcs_table(a, b, m))
    end
  end

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
