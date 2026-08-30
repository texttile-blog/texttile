defmodule Texttile.Stats do
  @moduledoc """
  How many people read the blog, counted by the blog itself.

  A reader page asks this server to count it, and this server writes
  one row. There is no cookie, no stored address, no third party and
  nothing to load from anywhere else. A reader is a hash of the day's
  salt, their address and their browser line, and the salt is gone at
  midnight (`Texttile.Stats.Salt`), so nobody is recognisable from one
  day to the next.

  Four rules keep the numbers about people. A browser that runs no
  script is not counted, which is most of what crawls the web. A
  browser line that says bot, and a page the browser only fetched
  ahead, are dropped here. The same reader on the same page counts
  once every half hour, so a reload changes nothing. And one caller
  writes at most a minute's worth of rows a minute, so nobody can sit
  down and invent an audience.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
  alias Texttile.Articles.Visibility
  alias Texttile.RateLimiter
  alias Texttile.Repo
  alias Texttile.Stats.Salt
  alias Texttile.Stats.View

  # The same reader on the same page, again inside this window, is the
  # same visit: a reload, a jump back, a second tab.
  @repeat_window_s 1_800

  # The counter's own bucket, wide enough for the fastest reader and
  # narrow enough that nobody writes an audience by hand.
  @limiter Texttile.Stats.Limiter
  @limiter_per_minute 60

  # How many rows a table of the Stats screen holds at most. Addresses
  # and sources are written by the caller, so their number is not the
  # blog's to trust.
  @rows 20

  # A host is at most this long. The name a browser sends is a name
  # somebody chose, and it is stored once per view.
  @host_max 120

  @doc "The name of the limiter in front of the counter."
  def limiter, do: @limiter

  @doc "How many views one caller may write in a minute."
  def limiter_per_minute, do: @limiter_per_minute

  @doc "How many rows the tables of the Stats screen hold at most."
  def rows, do: @rows

  # What a browser line says when it is not a person. Substrings, read
  # in lower case. The beacon keeps most crawlers out by itself - they
  # run no script - so this is the second net, not the first.
  @bots ~w(
    bot crawl spider slurp headless preview fetch monitor scan probe
    archiver validator lighthouse pingdom uptime phantomjs puppeteer
    playwright scrapy curl wget python- java/ go-http libwww okhttp
    httpclient httpx semrush ahrefs mediapartners facebookexternalhit
    embedly whatsapp yandex baidu sogou
  )

  ## Counting

  @doc """
  Counts one view, or says why it counted none.

  Takes `:path`, `:article_id`, `:referrer`, `:ip`, `:user_agent` and
  `:prefetch?`. Answers `:counted`, or `{:dropped, reason}` with
  `:bot`, `:prefetch`, `:bad_path`, `:repeat` or `:flood`.

  The limit is spent on storable views only, so a reader who reloads
  never loses a slot to the reload, and a caller past the limit is
  turned away before anything reads the database.

  `now:` names the moment the view is counted at, which decides both
  the day it belongs to and whether it repeats an earlier one. It
  defaults to this moment.
  """
  def count(attrs, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)

    with :ok <- from_a_person(attrs),
         {:ok, path} <- reader_path(attrs[:path]) do
      store(attrs, path, visitor(attrs[:ip], attrs[:user_agent]), now)
    end
  end

  defp store(attrs, path, visitor, now) do
    ip = to_string(attrs[:ip])

    cond do
      # A flood is turned away before anything reads the database. The
      # knock is not counted here, so a reader who reloads never loses
      # a slot to the reload: the slot is spent only when a row is
      # written.
      RateLimiter.over?(ip, @limiter) ->
        {:dropped, :flood}

      repeat?(visitor, path, now) ->
        {:dropped, :repeat}

      not RateLimiter.allow?(ip, @limiter) ->
        {:dropped, :flood}

      true ->
        Repo.insert!(%View{
          day: DateTime.to_date(now),
          path: path,
          article_id: readable_article_id(attrs[:article_id]),
          visitor: visitor,
          referrer_host: referrer_host(attrs[:referrer]),
          inserted_at: now
        })

        :counted
    end
  end

  @doc """
  The reader as the numbers know them: a hash of the day's salt, their
  address and their browser line. The salt is what makes it one-way,
  and it is gone tomorrow.
  """
  def visitor(ip, user_agent) do
    :sha256
    |> :crypto.hash([Salt.current(), to_string(ip), 0, to_string(user_agent)])
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end

  # A page the browser fetched before anybody asked for it was read by
  # nobody, and a browser line that says bot is no reader either. A
  # line that says nothing at all is not a browser: every one of them
  # sends one.
  defp from_a_person(attrs) do
    agent = attrs[:user_agent] |> to_string() |> String.downcase()

    cond do
      attrs[:prefetch?] -> {:dropped, :prefetch}
      agent == "" -> {:dropped, :bot}
      Enum.any?(@bots, &String.contains?(agent, &1)) -> {:dropped, :bot}
      true -> :ok
    end
  end

  # The address of a reader page, as it is stored: no query, no
  # fragment, no trailing slash. A query is how one page is read twice,
  # not how there are two pages.
  defp reader_path(path) when is_binary(path) do
    without_query = path |> String.split(["?", "#"], parts: 2) |> hd()

    trimmed =
      case String.trim_trailing(without_query, "/") do
        "" -> "/"
        trimmed -> trimmed
      end

    if String.starts_with?(without_query, "/") and not String.starts_with?(trimmed, "//") and
         byte_size(trimmed) <= 255 do
      {:ok, trimmed}
    else
      {:dropped, :bad_path}
    end
  end

  defp reader_path(_path), do: {:dropped, :bad_path}

  # The entry the page named, if a reader can read it at all. Anything
  # else is counted as a plain address: a caller writes this number,
  # and a draft or an entry that never existed must not collect views.
  defp readable_article_id(id) when is_integer(id) do
    if Repo.exists?(Visibility.live() |> where([a], a.id == ^id)) do
      id
    end
  end

  defp readable_article_id(_id), do: nil

  # Where the reader came from, as a host and nothing more. The blog's
  # own pages are no source: a reader walking from one entry to the
  # next arrived direct.
  defp referrer_host(referrer) when is_binary(referrer) do
    with %URI{host: host} when is_binary(host) <- URI.parse(referrer),
         host <- host |> String.downcase() |> String.replace_prefix("www.", ""),
         true <- host != "" and host != own_host() and byte_size(host) <= @host_max do
      host
    else
      _ -> nil
    end
  end

  defp referrer_host(_referrer), do: nil

  defp own_host do
    TexttileWeb.Endpoint.url() |> URI.parse() |> Map.get(:host) |> to_string()
  end

  defp repeat?(visitor, path, now) do
    since = DateTime.add(now, -@repeat_window_s, :second)

    Repo.exists?(
      from v in View,
        where: v.visitor == ^visitor and v.path == ^path and v.inserted_at > ^since
    )
  end

  ## The numbers the screens read

  @doc """
  A span of days the screens read: `from` the first day (nil for all
  time) `to` the last. `window(30)` is the last thirty days up to
  today, `window(:all)` is everything ever counted.

  A bar of the chart is a span too (`bar/2`), so what is read for
  the whole window is read for one bar with the same functions.

  `today:` names the last day, the way `count/2` takes `now:`.
  """
  def window(days, opts \\ [])

  def window(:all, opts), do: %{from: nil, to: today(opts)}

  def window(days, opts) when is_integer(days) do
    today = today(opts)
    %{from: Date.add(today, -(days - 1)), to: today}
  end

  @doc """
  Views, people and the busiest day of the span, and `before`: the
  views and people of the span of the same length just before it, so a
  figure can say how it moved. All time has nothing before it.

  A person is counted once a day, because that is as far as a visitor
  hash reaches. Somebody who reads on ten days is ten people here.
  """
  def summary(span) do
    # One row per day out of the database, never one row per view: the
    # table grows with the readers, and this screen must not grow with
    # it. Three numbers per day is all three figures need.
    rows =
      View
      |> in_span(span)
      |> group_by([v], v.day)
      |> select([v], {v.day, count(v.id), count(v.visitor, :distinct)})
      |> Repo.all()

    %{
      views: rows |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
      people: rows |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
      busiest:
        case Enum.max_by(rows, &elem(&1, 1), fn -> nil end) do
          nil -> nil
          {day, views, _people} -> {day, views}
        end,
      before: before(span)
    }
  end

  defp before(%{from: nil}), do: nil

  defp before(%{from: from, to: to}) do
    length = Date.diff(to, from) + 1

    View
    |> in_span(%{from: Date.add(from, -length), to: Date.add(from, -1)})
    |> select([v], %{views: count(v.id), people: count(v.visitor, :distinct)})
    |> Repo.one!()
  end

  @doc """
  One bar per step of the span, oldest first, every step present, each
  with its `from` and `to` day, its views and its people. Up to sixty
  days a step is a day, up to a year a week (Monday first), and above
  that a month. All time starts at the month of the first view, or at
  this month when nothing was counted yet.

  `article_id:` narrows it to one entry.
  """
  def series(span, opts \\ []) do
    bars = bars(span)

    counted =
      View
      |> in_span(%{from: List.first(bars).from, to: span.to})
      |> for_article(opts[:article_id])
      |> group_by([v], v.day)
      |> select([v], {v.day, count(v.id), count(v.visitor, :distinct)})
      |> Repo.all()

    Enum.map(bars, fn bar ->
      inside = Enum.filter(counted, fn {day, _, _} -> in_bar?(bar, day) end)

      Map.merge(bar, %{
        views: inside |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
        people: inside |> Enum.map(&elem(&1, 2)) |> Enum.sum()
      })
    end)
  end

  @doc "The bar of the span that holds `day`, or nil when none does."
  def bar(span, day) do
    Enum.find(bars(span), &in_bar?(&1, day))
  end

  defp in_bar?(%{from: from, to: to}, day) do
    Date.compare(day, from) != :lt and Date.compare(day, to) != :gt
  end

  defp bars(%{from: nil, to: to}) do
    first =
      View
      |> select([v], min(v.day))
      |> Repo.one()
      |> case do
        nil -> to
        day -> day
      end

    bars(:month, Date.beginning_of_month(first), to)
  end

  defp bars(%{from: from, to: to}) do
    case Date.diff(to, from) + 1 do
      days when days <= 60 -> bars(:day, from, to)
      days when days < 365 -> bars(:week, Date.beginning_of_week(from), to)
      _days -> bars(:month, Date.beginning_of_month(from), to)
    end
  end

  # From `from` in whole steps up to and including `to`, the last step
  # cut at `to`. The bars of a window all reach back to a whole step's
  # start, so a bar found by a day is the bar that was drawn.
  defp bars(step, from, to) do
    from
    |> Stream.iterate(&next(step, &1))
    |> Enum.take_while(&(Date.compare(&1, to) != :gt))
    |> Enum.map(fn start ->
      %{from: start, to: Enum.min([Date.add(next(step, start), -1), to], Date)}
    end)
  end

  defp next(:day, date), do: Date.add(date, 1)
  defp next(:week, date), do: Date.add(date, 7)
  defp next(:month, date), do: date |> Date.end_of_month() |> Date.add(1)

  @doc """
  The most read entries of the span, with the entry itself, its views
  and its people.
  """
  def top_articles(span, limit) do
    counted =
      View
      |> in_span(span)
      |> where([v], not is_nil(v.article_id))
      |> group_by([v], v.article_id)
      |> select([v], {v.article_id, count(v.id), count(v.visitor, :distinct)})
      |> order_by([v], desc: count(v.id))
      |> limit(^limit)
      |> Repo.all()

    articles = articles(Enum.map(counted, &elem(&1, 0)))

    for {id, views, people} <- counted, article = articles[id] do
      %{article: article, views: views, people: people}
    end
  end

  @doc """
  Everything read in the span, entries and other addresses in one
  list, most read first. An entry comes with `article`, any other page
  with `article: nil` and its address. This is what a clicked bar
  shows. At most `rows/0` of them, like the tables.
  """
  def pages_read(span) do
    counted =
      View
      |> in_span(span)
      |> group_by([v], [v.article_id, v.path])
      |> select([v], %{
        article_id: v.article_id,
        path: v.path,
        views: count(v.id),
        people: count(v.visitor, :distinct)
      })
      |> order_by([v], desc: count(v.id), asc: v.path)
      |> limit(@rows)
      |> Repo.all()

    articles = counted |> Enum.map(& &1.article_id) |> Enum.reject(&is_nil/1) |> articles()

    for row <- counted do
      %{article: articles[row.article_id], path: row.path, views: row.views, people: row.people}
    end
  end

  defp articles([]), do: %{}

  defp articles(ids) do
    from(a in Article, where: a.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  The reader pages that are no entry - the front door, the list, the
  tag archives - counted by address over the span, biggest first.

  At most `rows/0` of them: the address is written by the caller, so
  the number of different ones is theirs to choose, and a screen that
  draws a row per address is a screen they can make unusable.
  """
  def other_pages(span) do
    View
    |> in_span(span)
    |> where([v], is_nil(v.article_id))
    |> group_by([v], v.path)
    |> select([v], %{path: v.path, views: count(v.id)})
    |> order_by([v], desc: count(v.id), asc: v.path)
    |> limit(@rows)
    |> Repo.all()
  end

  @doc """
  Where the readers of the span came from, biggest source first, each
  with its share in whole percent. `host: nil` is a reader who arrived
  direct: a bookmark, a typed address, a mail program.

  At most `rows/0` sources, and for the same reason: the source comes
  from the caller too. The share is of every view of the span, so the
  sources left out are the difference to a hundred.

  `article_id:` narrows it to one entry.
  """
  def referrers(span, opts \\ []) do
    inside = View |> in_span(span) |> for_article(opts[:article_id])

    case Repo.aggregate(inside, :count) do
      0 ->
        []

      total ->
        inside
        |> group_by([v], v.referrer_host)
        |> select([v], %{host: v.referrer_host, views: count(v.id)})
        |> order_by([v], desc: count(v.id))
        |> limit(@rows)
        |> Repo.all()
        |> Enum.map(&Map.put(&1, :share, round(&1.views / total * 100)))
    end
  end

  @doc "How often one entry was read, for all time."
  def article_views(article_id) do
    Repo.aggregate(from(v in View, where: v.article_id == ^article_id), :count)
  end

  defp for_article(query, nil), do: query
  defp for_article(query, id), do: where(query, [v], v.article_id == ^id)

  defp in_span(query, %{from: nil, to: to}), do: where(query, [v], v.day <= ^to)

  defp in_span(query, %{from: from, to: to}),
    do: where(query, [v], v.day >= ^from and v.day <= ^to)

  defp today(opts), do: Keyword.get(opts, :today, Date.utc_today())
end
