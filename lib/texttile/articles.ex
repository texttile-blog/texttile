defmodule Texttile.Articles do
  @moduledoc """
  The texts: drafts, scheduled texts and published ones, their versions
  and their Log.

  The concurrency model, from the collaboration spec: the title and the
  body belong to one admin at a time (see `Texttile.Articles.Lock`);
  everything else is freely editable by every admin all the time, last
  write wins per field. Every accepted change is announced, on the admin
  topic for the grid and on the article's own topic for open editors.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
  alias Texttile.Articles.Body
  alias Texttile.Articles.LogEntry
  alias Texttile.Articles.Publishing
  alias Texttile.Articles.Redirect
  alias Texttile.Articles.Version
  alias Texttile.Articles.Visibility
  alias Texttile.Repo

  @admin_topic "articles"

  ## PubSub

  def subscribe_admin do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @admin_topic)
  end

  def subscribe(article_id) do
    Phoenix.PubSub.subscribe(Texttile.PubSub, topic(article_id))
  end

  defp topic(article_id), do: "article:#{article_id}"

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @admin_topic, message)

    case message do
      {_, %Article{id: id}} -> Phoenix.PubSub.broadcast(Texttile.PubSub, topic(id), message)
      {_, id} when is_integer(id) -> Phoenix.PubSub.broadcast(Texttile.PubSub, topic(id), message)
      _ -> :ok
    end
  end

  ## Reading

  def get_article!(id), do: Repo.get!(Article, id)

  @doc "One entry by id whatever state it is in, or nil."
  def get_article(id), do: Repo.get(Article, id)

  @doc """
  The texts for the grid, by date, newest first: the day a text is
  published or goes live, and while it carries no date yet, today - a
  draft is the newest thing in the admin area until it gets one.
  `filter:` narrows to one status ("all" and nil mean everything),
  `search:` looks through the title, the tags and the body,
  case-insensitively.
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
    |> order_by([a], desc: fragment("coalesce(?, date('now'))", a.publish_date), desc: a.id)
    |> Repo.all()
  end

  ## The public reading

  @doc """
  The published posts for the readers, newest publish date first.
  `search:` looks through the title, the tags and the full text.
  """
  def list_published(opts \\ []) do
    published_query("post")
    |> order_by([a], desc: a.publish_date, desc: a.id)
    |> Repo.all()
    |> search_filter(opts[:search] |> to_string() |> String.trim())
  end

  # The search runs in Elixir, not in SQL: SQLite's lower() and LIKE
  # only fold ASCII, so "über" would never find "Über" there, and a
  # reader's % or _ would act as wildcards. A published blog is small;
  # every word of the term must appear somewhere in the text.
  defp search_filter(articles, ""), do: articles

  defp search_filter(articles, search) do
    words = search |> String.downcase() |> String.split()

    Enum.filter(articles, fn article ->
      hay = String.downcase(article.title <> " " <> article.tags <> " " <> article.body)
      Enum.all?(words, &String.contains?(hay, &1))
    end)
  end

  @doc "One published text by id, post or page alike, or nil."
  def get_published(id) do
    Article |> Visibility.live() |> Repo.get_by(id: id)
  end

  @doc "The published pages for the site menu, oldest publish date first."
  def list_pages do
    published_query("page")
    |> order_by([a], asc: a.publish_date, asc: a.id)
    |> Repo.all()
  end

  @doc """
  The two posts a reader walks to from this one: `{older, newer}`, each
  nil at the end of the row. A page is not in the row and answers
  `{nil, nil}`; the list runs by publish date, with the id breaking a
  tie between two texts of the same day.
  """
  def neighbours(%Article{type: "post"} = article) do
    if Visibility.live?(article) do
      {neighbour(article, :older), neighbour(article, :newer)}
    else
      {nil, nil}
    end
  end

  def neighbours(%Article{}), do: {nil, nil}

  defp neighbour(article, :older) do
    published_query("post")
    |> where(
      [a],
      a.publish_date < ^article.publish_date or
        (a.publish_date == ^article.publish_date and a.id < ^article.id)
    )
    |> order_by([a], desc: a.publish_date, desc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  defp neighbour(article, :newer) do
    published_query("post")
    |> where(
      [a],
      a.publish_date > ^article.publish_date or
        (a.publish_date == ^article.publish_date and a.id > ^article.id)
    )
    |> order_by([a], asc: a.publish_date, asc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The address a text wears on the public site. A post lives under the
  day it went live, `/2026/08/23/harbor`; a page keeps the short
  address, `/about-us`, because the site menu points at it. A text
  without a slug, or a post without a date, has no address yet and
  answers nil.
  """
  def public_path(%Article{slug: slug}) when slug in [nil, ""], do: nil

  def public_path(%Article{type: "page", slug: slug} = article),
    do: public_prefix(article) <> slug

  def public_path(%Article{slug: slug, publish_date: %Date{}} = article),
    do: public_prefix(article) <> slug

  def public_path(%Article{}), do: nil

  @doc """
  What stands before the slug in the address: `/` for a page,
  `/2026/08/23/` for a post. A post without a date yet borrows today,
  which is the day it gets when somebody publishes it now. Takes a text
  or anything else that carries a type and a date, so the import can
  show the address a bundle will take.
  """
  def public_prefix(%{type: "page"}), do: "/"

  def public_prefix(%{publish_date: date}) do
    date = date || Date.utc_today()
    "/#{date.year}/#{pad2(date.month)}/#{pad2(date.day)}/"
  end

  defp pad2(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc "The published post at a date and a slug, or nil."
  def get_published_post(%Date{} = date, slug) when is_binary(slug) do
    Visibility.live()
    |> where([a], a.slug == ^slug and a.type == "post" and a.publish_date == ^date)
    |> Repo.one()
  end

  @doc "The published page behind a short address, or nil."
  def get_published_page(slug) when is_binary(slug) do
    Visibility.live()
    |> where([a], a.slug == ^slug and a.type == "page")
    |> Repo.one()
  end

  @doc """
  The post at a date and a slug whatever state it is in, or nil.

  An entry wears its address from the moment it has a slug, and an
  admin who is signed in reads it there before anybody else can: the
  reader's side of a draft is the reader's side, not a second design.
  """
  def get_post(%Date{} = date, slug) when is_binary(slug) do
    Repo.one(
      from a in Article, where: a.slug == ^slug and a.type == "post" and a.publish_date == ^date
    ) || dateless_post(date, slug)
  end

  # A post with no day yet borrows today, exactly as `public_prefix/1`
  # does, so the address the editor prints is the address that answers.
  # Tomorrow it borrows tomorrow, and so would publishing it.
  defp dateless_post(date, slug) do
    if Date.compare(date, Date.utc_today()) == :eq do
      Repo.one(
        from a in Article,
          where: a.slug == ^slug and a.type == "post" and is_nil(a.publish_date)
      )
    end
  end

  @doc """
  The address an entry can be read at right now, live or not: its
  public address, and while a post has no day yet, the address it
  borrows from today. Nil until the entry has a slug, because until
  then there is nothing to open.
  """
  def reader_path(%Article{slug: slug}) when slug in [nil, ""], do: nil

  def reader_path(%Article{slug: slug} = article),
    do: public_path(article) || public_prefix(article) <> slug

  @doc "The page behind a short address whatever state it is in, or nil."
  def get_page(slug) when is_binary(slug) do
    Repo.one(from a in Article, where: a.slug == ^slug and a.type == "page")
  end

  ## The archive: one line of years, the months of the open year

  @doc "The short name of a month, 1 to 12, in the language of the site."
  defdelegate month_name(number), to: Texttile.I18n, as: :short_month_name

  @doc """
  Whether an entry falls in a period. `nil` for the year means every
  year, `nil` for the month means the whole year. An entry without a
  publish date falls in no year at all: it is not in the archive until
  it has a day.
  """
  def in_period?(_article, nil, _month), do: true
  def in_period?(%{publish_date: nil}, _year, _month), do: false
  def in_period?(%{publish_date: date}, year, nil), do: date.year == year

  def in_period?(%{publish_date: date}, year, month),
    do: date.year == year and date.month == month

  @doc """
  The archive over a list of entries: `{years, months}`.

  `years` is every year the list touches, newest first, each with how
  many entries it holds. `months` is empty until a year is open, and
  then it holds only the months of that year that carry something: a
  month nobody wrote in is not a choice, and a row of twelve where half
  of them do nothing reads as a calendar.

  The counts come from the list as it stands, so they follow whatever
  the search has narrowed it to and a year that holds nothing for the
  term goes quiet instead of lying about it.
  """
  def periods(articles, year) do
    years =
      articles
      |> Enum.flat_map(fn
        %{publish_date: nil} -> []
        %{publish_date: date} -> [date.year]
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {y, _count} -> -y end)

    months =
      if year do
        for month <- 1..12,
            count = Enum.count(articles, &in_period?(&1, year, month)),
            count > 0,
            do: {month, count}
      else
        []
      end

    {years, months}
  end

  @doc """
  The year and the month a list can actually show, out of what was
  asked for. A search can empty the year that is open; then the year
  lets go, rather than showing a page with nothing on it.
  """
  def settle_period(articles, year, month) do
    year = if year && Enum.any?(articles, &in_period?(&1, year, nil)), do: year
    month = if year && month && Enum.any?(articles, &in_period?(&1, year, month)), do: month
    {year, month}
  end

  ## The addresses an entry has left behind

  @doc """
  The addresses this entry used to live at, newest first. The editor
  lists them under the address field, so whoever moved a text sees what
  the move left standing and can take a row off again.
  """
  def redirects(%Article{id: id}) do
    Redirect
    |> where([r], r.article_id == ^id)
    |> order_by([r], desc: r.id)
    |> Repo.all()
  end

  @doc """
  Where an old address sends a reader now, or nil when it sends nobody
  anywhere: no row, the entry left the site, or the row names the very
  address that was asked for.
  """
  def redirect_target(path) when is_binary(path) do
    with %Redirect{} = redirect <- Repo.get_by(Redirect, path: path),
         %Article{} = article <- live_article(redirect.article_id),
         target when is_binary(target) and target != path <- public_path(article) do
      target
    else
      _ -> nil
    end
  end

  def redirect_target(_path), do: nil

  defp live_article(id), do: Article |> Visibility.live() |> Repo.get(id)

  @doc "Takes one old address off the entry; it answers a 404 again."
  def delete_redirect(%Article{id: id}, redirect_id) do
    case Repo.get_by(Redirect, id: redirect_id, article_id: id) do
      nil -> :ok
      redirect -> with {:ok, _} <- Repo.delete(redirect), do: :ok
    end
  end

  # A live entry that moves leaves its address behind. Only a live one:
  # before an entry goes live nobody could reach the address, so there
  # is no link to keep alive.
  #
  # The address it moves to must answer the entry itself from now on, so
  # a row that claims it is dropped - that is what happens when somebody
  # moves a text and moves it straight back.
  # Nothing is written while nothing moved. Every article setting goes
  # through here - a tag, a checkbox, a keystroke in the tag field - and
  # a write on each of those would hold SQLite's one write lock for a
  # change that means nothing.
  defp remember_address(%Article{} = before, %Article{} = now) do
    if Visibility.live?(before), do: keep_old_address(before, now), else: now
  end

  defp keep_old_address(before, now) do
    old = public_path(before)
    new = public_path(now)

    if is_binary(old) and old != new do
      stamp = DateTime.utc_now(:second)

      Repo.insert(
        %Redirect{article_id: now.id, path: old, inserted_at: stamp},
        on_conflict: [set: [article_id: now.id, inserted_at: stamp]],
        conflict_target: :path
      )

      # Two live entries can never share an address, so a row claiming
      # the address this one just moved to belongs to an entry that
      # vacated it. From now on the address is this entry's own again.
      if is_binary(new), do: Repo.delete_all(from r in Redirect, where: r.path == ^new)
    end

    now
  end

  @doc """
  Every tag the admin area already knows, the most used one first, then
  in alphabetical order. The editor offers this list under the tag field,
  so the same word does not come back in three spellings.
  """
  def known_tags, do: Enum.map(tag_counts(), fn {tag, _count} -> tag end)

  @doc """
  The same list with the number of texts on each tag. Settings shows
  it, so whoever deletes a tag sees what it costs first.
  """
  def tag_counts do
    Article
    |> select([a], a.tags)
    |> Repo.all()
    |> Enum.flat_map(&tag_list(%{tags: &1}))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)
  end

  @doc """
  Takes a tag off every text that carries it, whatever it is spelled
  like there, and answers how many texts changed. The archive page of
  the tag is gone with the last text on it.
  """
  def delete_tag(tag) do
    wanted = tag |> to_string() |> String.trim() |> String.downcase()

    if wanted == "" do
      0
    else
      # The like narrows the rows the database hands over; a text
      # carries its whole body, and a blog of five hundred of them is
      # no reason to read them all. The word itself is checked after
      # that, so "sea" never takes "seawall" with it.
      like = "%#{wanted}%"

      Article
      |> where([a], like(fragment("lower(?)", a.tags), ^like))
      |> Repo.all()
      |> Enum.filter(&(wanted in tag_list(&1)))
      |> Enum.map(&drop_tag(&1, wanted))
      |> length()
    end
  end

  defp drop_tag(article, wanted) do
    kept =
      article.tags
      |> String.split(",")
      |> Enum.reject(&(&1 |> String.trim() |> String.downcase() == wanted))
      |> Enum.join(",")

    {:ok, article} = update_settings(article, %{tags: kept})
    article
  end

  @doc """
  The tags of a text as a clean list: split on commas, trimmed,
  lowercased, each tag once. Every tag is an archive page.
  """
  def tag_list(%{tags: tags}) do
    tags
    |> to_string()
    |> String.downcase()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp published_query(type) do
    Visibility.live() |> where([a], a.type == ^type)
  end

  ## Writing

  @doc "A new, empty draft, and the first line of its Log."
  def create_draft(user) do
    {:ok, article} = Repo.insert(%Article{})
    push_log(article, user, "started the entry")
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
    with {:ok, moved} <- article |> Article.settings_changeset(attrs) |> Repo.update() do
      moved = remember_address(article, moved)
      broadcast({:article_changed, moved})
      {:ok, moved}
    end
  end

  @doc """
  The one publish click. An empty or past date goes live today, a
  future date schedules; `force: true` (the "Publish now" of a
  scheduled text) goes live today regardless. Publishing writes a
  version snapshot, so "this is how it went live" is always restorable.
  """
  def publish(%Article{} = article, user, opts \\ []) do
    {day, status} = Publishing.landing(article, opts)
    went_live? = status == Visibility.live_status() and not Visibility.live?(article)

    attrs = %{status: status, publish_date: day, slug: article.slug || free_slug(article)}

    with {:ok, article} <- article |> Article.state_changeset(attrs) |> Repo.update() do
      snapshot(article, user)

      push_log(
        article,
        user,
        if(status == "scheduled",
          do: "scheduled the entry for #{day}",
          else: "published the entry"
        )
      )

      article = if went_live?, do: Texttile.Newsletter.notify_published(article), else: article

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
        if(was == "scheduled", do: "unscheduled the entry", else: "unpublished the entry")
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
        status = if Date.compare(date, today) == :gt, do: "scheduled", else: Visibility.live_status()

        # A scheduled text whose date is dragged to today goes live this
        # moment - that is a go-live like any other. A date edit on an
        # already-live text is not.
        went_live? = status == Visibility.live_status() and article.status == "scheduled"

        with {:ok, moved} <-
               article
               |> Article.state_changeset(%{publish_date: date, status: status})
               |> Repo.update() do
          # The date is part of the address of a post, so a live entry
          # that gets another day has moved and leaves the old day
          # standing as a redirect.
          moved = remember_address(article, moved)

          moved = if went_live?, do: Texttile.Newsletter.notify_published(moved), else: moved

          broadcast({:article_changed, moved})
          {:ok, moved}
        end
    end
  end

  @doc """
  Scheduled texts whose day has come go live, and the subscriber email
  goes out for each of them. Returns the texts that went live.
  """
  def go_live_due(today \\ Date.utc_today()) do
    Article
    |> where([a], a.status == "scheduled" and a.publish_date <= ^today)
    |> Repo.all()
    |> Enum.map(fn article ->
      {:ok, article} =
        article
        |> Article.state_changeset(%{status: Visibility.live_status()})
        |> Repo.update()
      push_log(article, nil, "the entry went live as scheduled")
      article = Texttile.Newsletter.notify_published(article)
      broadcast({:article_changed, article})
      article
    end)
  end

  @doc """
  Deletes the text and everything that hangs on it, the images in the
  body included: versions never guard an image, so the files go at
  once - no orphan retention, no reference counting.
  """
  def delete_article(%Article{} = article) do
    bodies = [
      article.body
      | Version
        |> where([v], v.article_id == ^article.id)
        |> select([v], v.body)
        |> Repo.all()
    ]

    # Read before the delete: the gallery rows go with the article row.
    gallery_paths = Texttile.Gallery.paths(article.id)

    with {:ok, article} <- Repo.delete(article) do
      bodies
      |> Enum.flat_map(&Body.upload_paths/1)
      |> Enum.uniq()
      |> Enum.concat(gallery_paths)
      |> Enum.each(&Texttile.Uploads.remove_upload/1)

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
        push_log(article, user, "saved a version of the entry")
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

  defp stamp(datetime), do: Texttile.I18n.format_moment(datetime)

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

  @doc "The name a text goes by on screen: its title, or Untitled."
  def display_title(%{title: ""}), do: Gettext.gettext(TexttileWeb.Gettext, "Untitled")
  def display_title(%{title: title}), do: title

  @doc """
  The lead line of a text: the first real paragraph, the markdown
  stripped, cut at a word before 160 characters. The cards of the
  public list carry it, and so does the subscriber mail.
  """
  def lead(article) do
    article.body
    |> to_string()
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&String.trim/1)
    |> Enum.find("", fn block ->
      block != "" and not String.starts_with?(block, "#") and
        not Regex.match?(~r/\A!\[[^\]]*\]\([^)]*\)\z/, block)
    end)
    |> strip_markdown()
    |> shorten(160)
  end

  defp strip_markdown(text) do
    text
    |> String.replace(~r/!\[[^\]]*\]\([^)]*\)/, "")
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[*_`>]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp shorten(text, max) do
    if String.length(text) <= max do
      text
    else
      # the slice ends mid-word, so the broken tail goes - unless the
      # cut is one single word, which stays as it is
      cut = String.slice(text, 0, max)

      head =
        case String.split(cut, " ") do
          [_single] -> cut
          words -> words |> Enum.drop(-1) |> Enum.join(" ")
        end

      head <> "…"
    end
  end

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

    # The site's own addresses count as taken, like another text's slug.
    taken =
      Article
      |> where([a], like(a.slug, ^"#{base}%") and a.id != ^article.id)
      |> select([a], a.slug)
      |> Repo.all()
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Article.reserved_slugs()))

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

  The untouched head and tail of the text are peeled off before the
  LCS runs, so a long article with a small edit still gets a real
  diff; only a rewrite of half a book falls back to "all new".
  """
  def diff(old_text, new_text) do
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
