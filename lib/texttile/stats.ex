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
  never loses a slot to the reload.

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
    cond do
      repeat?(visitor, path, now) ->
        {:dropped, :repeat}

      not RateLimiter.allow?(to_string(attrs[:ip]), @limiter) ->
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
  Views, people and the busiest day of the last `days` days.

  A person is counted once a day, because that is as far as a visitor
  hash reaches. Somebody who reads on ten days is ten people here.
  """
  def summary(days) do
    # One row per day out of the database, never one row per view: the
    # table grows with the readers, and this screen must not grow with
    # it. Three numbers per day is all three figures need.
    rows =
      View
      |> where([v], v.day >= ^first_day(days))
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
        end
    }
  end

  @doc """
  One number per day of the window, oldest first, every day present.

  `article_id:` narrows it to one entry.
  """
  def by_day(days, opts \\ []) do
    first = first_day(days)

    counted =
      View
      |> where([v], v.day >= ^first)
      |> for_article(opts[:article_id])
      |> group_by([v], v.day)
      |> select([v], {v.day, count(v.id)})
      |> Repo.all()
      |> Map.new()

    Enum.map(0..(days - 1), fn n ->
      day = Date.add(first, n)
      %{day: day, views: Map.get(counted, day, 0)}
    end)
  end

  @doc "The most read entries of all time, with the entry itself."
  def top_articles(limit) do
    counted =
      View
      |> where([v], not is_nil(v.article_id))
      |> group_by([v], v.article_id)
      |> select([v], {v.article_id, count(v.id)})
      |> order_by([v], desc: count(v.id))
      |> limit(^limit)
      |> Repo.all()

    articles =
      from(a in Article, where: a.id in ^Enum.map(counted, &elem(&1, 0)))
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    for {id, views} <- counted, article = articles[id], do: %{article: article, views: views}
  end

  @doc """
  The reader pages that are no entry - the front door, the list, the
  tag archives - counted by address over the window, biggest first.

  At most `rows/0` of them: the address is written by the caller, so
  the number of different ones is theirs to choose, and a screen that
  draws a row per address is a screen they can make unusable.
  """
  def other_pages(days) do
    View
    |> where([v], v.day >= ^first_day(days) and is_nil(v.article_id))
    |> group_by([v], v.path)
    |> select([v], %{path: v.path, views: count(v.id)})
    |> order_by([v], desc: count(v.id), asc: v.path)
    |> limit(@rows)
    |> Repo.all()
  end

  @doc """
  Where the readers of the window came from, biggest source first,
  each with its share in whole percent. `host: nil` is a reader who
  arrived direct: a bookmark, a typed address, a mail program.

  At most `rows/0` sources, and for the same reason: the source comes
  from the caller too. The share is of every view of the window, so
  the sources left out are the difference to a hundred.
  """
  def referrers(days, opts \\ []) do
    window =
      View
      |> where([v], v.day >= ^first_day(days))
      |> for_article(opts[:article_id])

    case Repo.aggregate(window, :count) do
      0 ->
        []

      total ->
        window
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

  defp first_day(days), do: Date.add(Date.utc_today(), -(days - 1))
end
