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

  # The author and the published version travel with every entry the
  # admin area opens: one names it, the other is the text the readers
  # have, and both are asked for on every screen that shows an entry.
  @with_people [:user, :live_version]

  def get_article!(id), do: Article |> Repo.get!(id) |> Repo.preload(@with_people)

  @doc "One entry by id whatever state it is in, or nil."
  def get_article(id), do: Article |> Repo.get(id) |> preload_people()

  defp preload_people(nil), do: nil
  defp preload_people(article), do: Repo.preload(article, @with_people)

  @doc """
  The displayed name of whoever started the entry, or nil where the
  account has gone. The name is read now and not stored, so a rename
  reaches every entry that person ever wrote.
  """
  def author_name(%Article{user: %Ecto.Association.NotLoaded{}} = article) do
    article |> Repo.preload(:user) |> author_name()
  end

  def author_name(%Article{user: nil}), do: nil
  def author_name(%Article{user: user}), do: Texttile.Accounts.display_name(user)

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
    |> preload(:user)
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
      # The published text, not the working copy: the field must find
      # what the list shows, and it shows what the reader has.
      read = as_read(article)
      hay = String.downcase(read.title <> " " <> read.tags <> " " <> read.body)
      Enum.all?(words, &String.contains?(hay, &1))
    end)
  end

  @doc """
  The entry as a reader gets it: the title and the body of the version
  that is live, and everything else as it stands.

  A live entry has two texts. The columns on the entry are the working
  copy, which is what the editor writes into and what an admin sees on
  the site; `live_version` is what was published, and that is this.
  Everything the version does not hold - the tags, the address, the
  tiles, the switches - has one state only and needs no choosing.

  An entry that has never been live has no second text and is returned
  as it is, so a draft an admin previews reads exactly as it is
  written.
  """
  def as_read(articles) when is_list(articles), do: Enum.map(articles, &as_read/1)

  def as_read(%Article{live_version: %Ecto.Association.NotLoaded{}} = article) do
    article |> Repo.preload(:live_version) |> as_read()
  end

  def as_read(%Article{live_version: %Version{} = version} = article) do
    if Visibility.live?(article) do
      %{article | title: version.title, body: version.body}
    else
      article
    end
  end

  def as_read(%Article{} = article), do: article

  @doc """
  Does the working copy of a live entry say something the readers have
  not been given yet?
  """
  def unpublished_changes?(%Article{live_version: %Ecto.Association.NotLoaded{}} = article) do
    article |> Repo.preload(:live_version) |> unpublished_changes?()
  end

  def unpublished_changes?(%Article{live_version: %Version{} = version} = article) do
    Visibility.live?(article) and
      (article.title != version.title or article.body != version.body)
  end

  def unpublished_changes?(%Article{}), do: false

  @doc """
  The ids of the live entries whose working copy has run ahead of what
  the readers have. One query for the whole overview, because the
  bodies of every entry are too much to carry there twice.
  """
  def entries_with_unpublished_changes do
    from(a in Article,
      join: v in Version,
      on: v.id == a.live_version_id,
      where: a.status == ^Visibility.live_status(),
      where: a.title != v.title or a.body != v.body,
      select: a.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "One published text by id, post or page alike, or nil."
  def get_published(id) do
    Article
    |> Visibility.live()
    |> preload([:user, :live_version])
    |> Repo.get_by(id: id)
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

  @doc """
  The address an entry can be read at right now, live or not: its
  public address, and while a post has no day yet, the address it
  borrows from today. Nil until the entry has a slug, because until
  then there is nothing to open.
  """
  def reader_path(%Article{slug: slug}) when slug in [nil, ""], do: nil

  def reader_path(%Article{slug: slug} = article),
    do: public_path(article) || public_prefix(article) <> slug

  @doc "The short name of a month, 1 to 12, in the language of the site."
  defdelegate month_name(number), to: Texttile.I18n, as: :short_month_name

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

  # Every reader query carries the author, who stands beside the day,
  # and the published version, which is the text itself. Loading them
  # here means no reader page can forget either.
  defp published_query(type) do
    Visibility.live() |> where([a], a.type == ^type) |> preload([:user, :live_version])
  end

  ## Writing

  @doc "A new, empty draft, and the first line of its Log."
  def create_draft(user) do
    {:ok, article} = Repo.insert(%Article{user_id: user && user.id})
    article = Repo.preload(article, :user)
    push_log(article, user, "started the entry")
    broadcast({:article_changed, article})
    {:ok, article}
  end

  @doc """
  The autosave: writes the title and the body into the working state.
  No log line and no version; typing is not an event.

  On a live entry this is where the two texts come apart: the readers
  keep the version that was published until somebody publishes this
  one.
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
  scheduled text) goes live today regardless.

  Publishing writes a version snapshot and hands the readers that
  version. From then on the entry has two texts, and a keystroke only
  moves the working copy: what stands here is what the site says until
  somebody publishes again. A scheduling stamps nothing, because
  nothing is live yet; the go-live does it.
  """
  def publish(%Article{} = article, user, opts \\ []) do
    {day, status} = Publishing.landing(article, opts)
    went_live? = status == Visibility.live_status() and not Visibility.live?(article)

    attrs = %{status: status, publish_date: day, slug: article.slug || free_slug(article)}

    with {:ok, article} <- article |> Article.state_changeset(attrs) |> Repo.update() do
      article =
        if status == Visibility.live_status() do
          hand_to_readers(article, user)
        else
          snapshot(article, user)
          article
        end

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

  @doc """
  Publish the changes: the working copy of a live entry becomes the
  text the readers have. Nothing else moves - the same day, the same
  address, the same state, and no mail. The mail belongs to the entry
  going out, not to a correction in it.
  """
  def publish_changes(%Article{} = article, user) do
    if unpublished_changes?(article) do
      article = hand_to_readers(article, user)
      push_log(article, user, "published the changes")
      broadcast({:article_changed, article})
      {:ok, article}
    else
      :unchanged
    end
  end

  @doc """
  Throw the unpublished changes away: the working copy goes back to the
  text the readers have. The state before is snapshotted first, exactly
  as a restore is, so nothing written is ever lost by this.
  """
  def discard_changes(%Article{} = article, user) do
    article = Repo.preload(article, :live_version)

    if unpublished_changes?(article) do
      restore_version(article, article.live_version, user)
    else
      :unchanged
    end
  end

  # The text as it stands becomes the version the readers get. The
  # snapshot deduplicates, so publishing an entry twice without a
  # change in between writes one version and points at it twice.
  defp hand_to_readers(%Article{} = article, user) do
    version =
      case snapshot(article, user) do
        {:ok, version} -> version
        :unchanged -> newest_version(article)
      end

    {:ok, article} =
      article
      |> Ecto.Changeset.change(live_version_id: version && version.id)
      |> Repo.update()

    %{article | live_version: version}
  end

  defp newest_version(%Article{id: id}) do
    Version
    |> where([v], v.article_id == ^id)
    |> order_by([v], desc: v.id)
    |> limit(1)
    |> Repo.one()
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
        status =
          if Date.compare(date, today) == :gt, do: "scheduled", else: Visibility.live_status()

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

          # A date dragged back onto today is a go-live, so the words
          # as they stand become the words the readers get. Without
          # this the entry would be live with no published version
          # behind it, and every later keystroke would be on the site.
          moved = if went_live?, do: hand_to_readers(moved, user), else: moved

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

      # The words as they stand on the morning it goes out are the
      # words the readers get; everything written after that waits for
      # a publish like any other change.
      article = hand_to_readers(article, nil)

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

  ## The pictures an entry holds

  @doc """
  Runs `fun` with this entry's pictures held still.

  Both clients upload two files at a time, so two requests carrying the
  same photograph can be in the air together. Without this they would
  both read the entry before either had written to it, both find
  nothing, and both store: the two tiles this whole check exists to
  prevent. Asking and storing happen inside one gate per entry, so the
  second one reads what the first one wrote.
  """
  def with_pictures_held(%Article{} = article, fun) do
    :global.trans({{__MODULE__, :pictures, article.id}, self()}, fun)
  end

  @doc """
  The picture this entry already holds that is the same file as the one
  at `source_path`, named the way a person would name it, or nil.

  An entry takes each picture once. The bytes decide, not the name, and
  the reach is this entry: the same photograph may stand in another one.

  Three things count as held: a tile of the gallery, a picture inside
  the text, and a picture that came in through this entry and is not on
  the volume any more only when its file has gone. So a tile in its undo
  window still holds its picture, which is what keeps undo from
  producing the pair, and a picture pasted into the text counts from the
  moment it lands, not from the moment the text is saved.
  """
  def duplicate_picture(%Article{} = article, source_path) do
    tiles = Texttile.Gallery.rows(article.id)

    paths =
      Enum.map(tiles, & &1.path) ++
        Body.upload_paths(article.body) ++
        Texttile.Uploads.paths_of_article(article.id)

    case Texttile.Uploads.duplicate(Texttile.Uploads.digest(source_path), paths) do
      nil -> nil
      path -> name_of(tiles, path)
    end
  end

  # A tile answers with the name it arrived under; a picture inside the
  # text has only the name it is stored as.
  defp name_of(tiles, path) do
    case Enum.find(tiles, &(&1.path == path)) do
      nil -> Path.basename(path)
      tile -> tile.filename
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
    newest = newest_version(article)

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
  The lead line of a text: its first sentences, the markdown stripped,
  cut at a word before 160 characters. The cards of the public list
  carry it, and so does the subscriber mail.

  It reads over the blank lines. The first paragraph alone is often one
  short line, and a card that carries "So, the way home." beside a card
  that carries four full lines makes a ragged grid. So the words of the
  text run together into one line, whatever the writer broke them into,
  and the cut is what ends it.

  Headings, rules and lines that are nothing but a picture are not
  words a reader wants in a lead; they go before the run.
  """
  def lead(article) do
    article.body
    |> to_string()
    |> String.split("\n")
    |> Enum.reject(&furniture?/1)
    |> Enum.map(&unmark/1)
    |> Enum.join(" ")
    |> strip_markdown()
    |> shorten(160)
  end

  # A line that carries no words of the text: a heading, a rule, a
  # fence, or a line that is nothing but one picture.
  defp furniture?(line) do
    line = String.trim(line)

    Regex.match?(~r/\A\#{1,6}\s/, line) or
      Regex.match?(~r/\A(-{3,}|\*{3,}|_{3,})\z/, line) or
      String.starts_with?(line, "```") or
      Regex.match?(~r/\A!\[[^\]]*\]\([^)]*\)\z/, line)
  end

  # What stands in front of a line and is not a word: the bullet of a
  # list, the number of a step, the mark of a quote.
  defp unmark(line) do
    String.replace(line, ~r/\A\s{0,3}(?:[-+*]\s+|\d+[.)]\s+|>\s*)/, "")
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
