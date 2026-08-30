defmodule Texttile.StatsTest do
  use Texttile.DataCase

  import Texttile.ArticlesFixtures
  import Texttile.StatsFixtures

  alias Texttile.Stats

  @agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
           "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"

  # The flood limiter lives beside the database and no sandbox rolls it
  # back. Every caller in this file wears the same address, so without
  # this the last tests of a run would meet a limit the first ones
  # spent.
  setup do
    Texttile.RateLimiter.reset(Stats.limiter())
    :ok
  end

  defp view(attrs \\ %{}) do
    %{
      path: "/blog",
      article_id: nil,
      referrer: nil,
      ip: "203.0.113.9",
      user_agent: @agent,
      prefetch?: false
    }
    |> Map.merge(Map.new(attrs))
  end

  describe "count/1: what is a person" do
    test "a browser on a reader page is one view" do
      assert :counted = Stats.count(view())
      assert Stats.summary(Stats.window(30)).views == 1
    end

    test "the same person on the same page counts once for half an hour" do
      assert :counted = Stats.count(view())
      assert {:dropped, :repeat} = Stats.count(view())
      assert Stats.summary(Stats.window(30)).views == 1
    end

    test "the same person on another page counts again" do
      assert :counted = Stats.count(view())
      assert :counted = Stats.count(view(%{path: "/2026/08/08/a-text"}))
      assert Stats.summary(Stats.window(30)).views == 2
    end

    test "a repeat after the window counts again" do
      now = DateTime.utc_now(:second)
      assert :counted = Stats.count(view(), now: now)

      # An hour on, past the window: the same person, a new visit.
      assert :counted = Stats.count(view(), now: DateTime.add(now, 3600, :second))
      assert Stats.summary(Stats.window(30)).views == 2
    end

    test "two addresses are two people, one address is one" do
      assert :counted = Stats.count(view(%{ip: "203.0.113.9"}))
      assert :counted = Stats.count(view(%{ip: "198.51.100.4", path: "/blog"}))

      assert Stats.summary(Stats.window(30)).people == 2
    end

    test "the same address in another browser is another person" do
      assert :counted = Stats.count(view())
      assert :counted = Stats.count(view(%{user_agent: @agent <> " Firefox/128.0"}))

      assert Stats.summary(Stats.window(30)).people == 2
    end

    test "the visitor is a hash, so no address is ever stored" do
      assert :counted = Stats.count(view())
      view = Repo.one!(Texttile.Stats.View)

      refute view.visitor =~ "203.0.113.9"
      assert String.length(view.visitor) == 32
    end
  end

  describe "count/1: what is not a person" do
    test "a bot user agent is dropped" do
      for agent <- [
            "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
            "Twitterbot/1.0",
            "Mozilla/5.0 (compatible; SemrushBot/7~bl)",
            "curl/8.4.0",
            "python-requests/2.31.0",
            "Mozilla/5.0 HeadlessChrome/126.0 Safari/537.36",
            "Mediapartners-Google",
            "facebookexternalhit/1.1"
          ] do
        assert {:dropped, :bot} = Stats.count(view(%{user_agent: agent}))
      end

      assert Stats.summary(Stats.window(30)).views == 0
    end

    test "no user agent at all is dropped" do
      assert {:dropped, :bot} = Stats.count(view(%{user_agent: nil}))
      assert {:dropped, :bot} = Stats.count(view(%{user_agent: ""}))
    end

    test "a page the browser only prefetched is dropped" do
      assert {:dropped, :prefetch} = Stats.count(view(%{prefetch?: true}))
    end

    test "an address that is no reader page is dropped" do
      for path <- ["", "nonsense", "//evil.example.com", "/" <> String.duplicate("x", 300)] do
        assert {:dropped, :bad_path} = Stats.count(view(%{path: path}))
      end
    end
  end

  describe "count/1: the flood" do
    test "a caller past the limit writes no more rows" do
      for n <- 1..Stats.limiter_per_minute() do
        assert :counted = Stats.count(view(%{path: "/page-#{n}"}))
      end

      assert {:dropped, :flood} = Stats.count(view(%{path: "/page-late"}))
      assert {:dropped, :flood} = Stats.count(view(%{path: "/page-later"}))
    end

    # The turn-away happens before anything reads the database: a flood
    # costs the installation no query, only the answer.
    test "a caller past the limit touches no database" do
      for n <- 1..Stats.limiter_per_minute() do
        Stats.count(view(%{path: "/page-#{n}"}))
      end

      counter = :counters.new(1, [:atomics])
      me = self()
      ref = "stats-flood-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          ref,
          [:texttile, :repo, :query],
          fn _event, _measurements, _metadata, _config ->
            if self() == me, do: :counters.add(counter, 1, 1)
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:dropped, :flood} = Stats.count(view(%{path: "/page-late"}))
      assert :counters.get(counter, 1) == 0
    end

    # A reload is not a knock: the same reader on the same page spends
    # nothing of the limit, so the fresh pages of the same minute keep
    # counting.
    test "a reload never loses a slot to the repeat" do
      assert :counted = Stats.count(view())

      for _ <- 1..Stats.limiter_per_minute() do
        assert {:dropped, :repeat} = Stats.count(view())
      end

      assert :counted = Stats.count(view(%{path: "/another-page"}))
    end
  end

  describe "count/1: what it stores" do
    test "the query and a trailing slash are not part of the address" do
      assert :counted = Stats.count(view(%{path: "/blog?page=2&q=trains"}))
      assert Repo.one!(Texttile.Stats.View).path == "/blog"

      assert :counted = Stats.count(view(%{ip: "198.51.100.4", path: "/tags/trains/"}))
      assert "/tags/trains" in Enum.map(Repo.all(Texttile.Stats.View), & &1.path)
    end

    test "a view belongs to the entry it names" do
      article = published_post(%{title: "Concrete flowers"})

      assert :counted = Stats.count(view(%{path: "/x", article_id: article.id}))
      assert Repo.one!(Texttile.Stats.View).article_id == article.id
    end

    test "an entry nobody can read is no entry" do
      draft = draft_post()

      assert :counted = Stats.count(view(%{article_id: draft.id}))
      assert Repo.one!(Texttile.Stats.View).article_id == nil

      assert :counted = Stats.count(view(%{ip: "198.51.100.4", article_id: 987_654}))
      assert Enum.all?(Repo.all(Texttile.Stats.View), &is_nil(&1.article_id))
    end

    test "the referrer is kept as a host, and www is not part of it" do
      assert :counted = Stats.count(view(%{referrer: "https://www.Example.COM/a/b?c=d"}))
      assert Repo.one!(Texttile.Stats.View).referrer_host == "example.com"
    end

    test "a link from the blog to itself is no referrer" do
      host = URI.parse(TexttileWeb.Endpoint.url()).host

      assert :counted = Stats.count(view(%{referrer: "http://#{host}/blog"}))
      assert Repo.one!(Texttile.Stats.View).referrer_host == nil
    end

    test "no referrer and a broken one both mean direct" do
      assert :counted = Stats.count(view(%{referrer: nil}))
      assert :counted = Stats.count(view(%{ip: "198.51.100.4", referrer: "not an address"}))

      assert Enum.all?(Repo.all(Texttile.Stats.View), &is_nil(&1.referrer_host))
    end
  end

  describe "the daily salt" do
    # The salt lives in one process for the whole run and no sandbox
    # rolls it back. A test that turns the day here leaves the salt it
    # read behind for everybody, so it turns the day once more on the
    # way out: what the next test finds is a secret no test has seen.
    setup do
      on_exit(&Stats.Salt.roll/0)
      :ok
    end

    test "yesterday's salt is gone, so nobody is recognised across days" do
      today = Stats.Salt.current()

      Stats.Salt.roll()

      refute Stats.Salt.current() == today
    end

    test "one visitor is one hash for as long as the salt stands" do
      today = Stats.visitor("203.0.113.9", @agent)

      assert Stats.visitor("203.0.113.9", @agent) == today

      Stats.Salt.roll()

      refute Stats.visitor("203.0.113.9", @agent) == today
    end
  end

  describe "the numbers the screens read" do
    setup do
      article = published_post(%{title: "Concrete flowers", publish_date: ~D[2026-05-30]})
      other = published_post(%{title: "Slow trains", publish_date: ~D[2026-06-21]})
      %{article: article, other: other}
    end

    test "a window reaches back from today, and all reaches to the first view" do
      today = ~D[2026-08-30]

      assert Stats.window(30, today: today) == %{from: ~D[2026-08-01], to: today}
      assert Stats.window(:all, today: today) == %{from: nil, to: today}
    end

    test "summary counts views, people, the busiest day and the window before", %{
      article: article
    } do
      seed_views(3, article_id: article.id)
      seed_views(5, article_id: article.id, day: Date.add(Date.utc_today(), -1))
      seed_views(9, article_id: article.id, day: Date.add(Date.utc_today(), -40))

      summary = Stats.summary(Stats.window(30))

      assert summary.views == 8
      assert summary.people == 8
      assert summary.busiest == {Date.add(Date.utc_today(), -1), 5}
      assert summary.before == %{views: 9, people: 9}
    end

    test "a blog nobody read yet has a summary too, and all time has no before" do
      assert Stats.summary(Stats.window(30)) == %{
               views: 0,
               people: 0,
               busiest: nil,
               before: %{views: 0, people: 0}
             }

      assert Stats.summary(Stats.window(:all)).before == nil
    end

    test "a short window is drawn in days, every day present, oldest first" do
      seed_views(2)

      series = Stats.series(Stats.window(30))

      assert length(series) == 30
      assert List.first(series).from == Date.add(Date.utc_today(), -29)
      today = Date.utc_today()
      assert List.last(series) == %{from: today, to: today, views: 2, people: 2}
      yesterday = Date.add(today, -1)
      assert Enum.at(series, 28) == %{from: yesterday, to: yesterday, views: 0, people: 0}
    end

    test "ninety days are drawn in weeks that start on a Monday" do
      today = ~D[2026-08-30]
      seed_views(1, day: ~D[2026-08-25])
      seed_views(1, day: ~D[2026-08-30])

      # The day before the window sits in the same week as its first
      # day. It is in no bar: the chart counts what the figures count.
      seed_views(5, day: ~D[2026-06-01])

      window = Stats.window(90, today: today)
      series = Stats.series(window)

      assert Stats.step(window) == :week
      assert length(series) == 13

      assert List.first(series) == %{
               from: ~D[2026-06-02],
               to: ~D[2026-06-07],
               views: 0,
               people: 0
             }

      assert Date.day_of_week(Enum.at(series, 1).from) == 1
      assert List.last(series) == %{from: ~D[2026-08-24], to: today, views: 2, people: 2}
      assert Stats.bar(window, ~D[2026-06-01]) == nil
    end

    test "a year and all time are drawn in months, from the first view on" do
      today = ~D[2026-08-30]
      seed_views(1, day: ~D[2025-11-03])

      seed_views(2, day: ~D[2025-08-30])

      year = Stats.window(365, today: today)
      assert Stats.step(year) == :month
      year = Stats.series(year)
      assert length(year) == 13
      assert List.first(year) == %{from: ~D[2025-08-31], to: ~D[2025-08-31], views: 0, people: 0}
      assert List.last(year) == %{from: ~D[2026-08-01], to: today, views: 0, people: 0}

      all = Stats.window(:all, today: today)
      assert Stats.step(all) == :month
      all = Stats.series(all)
      assert length(all) == 13
      assert List.first(all) == %{from: ~D[2025-08-01], to: ~D[2025-08-31], views: 2, people: 2}
      assert Enum.at(all, 3) == %{from: ~D[2025-11-01], to: ~D[2025-11-30], views: 1, people: 1}
    end

    test "all time with nothing counted is this month alone" do
      today = ~D[2026-08-30]

      assert [%{from: ~D[2026-08-01], to: ^today, views: 0}] =
               Stats.series(Stats.window(:all, today: today))
    end

    test "a bar is found by any day inside it" do
      today = ~D[2026-08-30]
      window = Stats.window(90, today: today)

      assert Stats.bar(window, ~D[2026-08-26]) == %{from: ~D[2026-08-24], to: today}
      assert Stats.bar(window, ~D[2026-01-01]) == nil
      assert Stats.bar(window, ~D[2027-01-01]) == nil
    end

    test "top entries are counted for the window, most read first, with their people", %{
      article: article,
      other: other
    } do
      seed_views(4, article_id: article.id, day: Date.add(Date.utc_today(), -200))
      seed_views(7, article_id: other.id)
      seed_views(1, article_id: article.id)

      assert [first, second] = Stats.top_articles(Stats.window(30), 10)
      assert first.article.id == other.id
      assert first.views == 7
      assert first.people == 7
      assert second.article.id == article.id
      assert second.views == 1

      assert [%{views: 7}, %{views: 5}] = Stats.top_articles(Stats.window(:all), 10)
    end

    test "an entry nobody read is not in the table", %{article: article} do
      seed_views(1, article_id: article.id)

      assert [row] = Stats.top_articles(Stats.window(30), 10)
      assert row.article.id == article.id
    end

    test "what was read in a span lists entries and other addresses together", %{
      article: article
    } do
      seed_views(3, article_id: article.id, path: "/2026/05/30/concrete-flowers")
      seed_views(2, path: "/blog")
      seed_views(1, path: "/blog", day: Date.add(Date.utc_today(), -1))

      today = Date.utc_today()
      assert [entry, blog] = Stats.pages_read(%{from: today, to: today})
      assert entry.article.id == article.id
      assert entry.views == 3
      assert blog == %{article: nil, path: "/blog", views: 2, people: 2}
    end

    test "the pages that are no entry are counted by address" do
      seed_views(3, path: "/blog")
      seed_views(1, path: "/tags/trains")

      assert [blog, tag] = Stats.other_pages(Stats.window(30))
      assert blog == %{path: "/blog", views: 3}
      assert tag == %{path: "/tags/trains", views: 1}
    end

    test "referrers carry their share of the window, biggest first" do
      seed_views(3, path: "/blog", referrer_host: "news.ycombinator.com")
      seed_views(1, path: "/blog", referrer_host: "lobste.rs")

      assert [hn, lobsters] = Stats.referrers(Stats.window(30))
      assert hn == %{host: "news.ycombinator.com", views: 3, share: 75}
      assert lobsters == %{host: "lobste.rs", views: 1, share: 25}
    end

    test "the tables hold a bounded number of rows, whatever a caller writes" do
      # The address and the source come from the caller, so the number
      # of different ones is theirs to choose. The screen's is not.
      for n <- 1..(Stats.rows() + 5) do
        seed_views(1, path: "/made-up-#{n}", referrer_host: "host#{n}.example")
      end

      assert length(Stats.other_pages(Stats.window(30))) == Stats.rows()
      assert length(Stats.referrers(Stats.window(30))) == Stats.rows()
      assert length(Stats.pages_read(Stats.window(30))) == Stats.rows()
    end

    test "a share is of every view of the window, not of the rows shown" do
      seed_views(1, path: "/blog", referrer_host: "lobste.rs")
      seed_views(3, path: "/blog")

      assert %{host: nil, views: 3, share: 75} =
               Enum.find(Stats.referrers(Stats.window(30)), &is_nil(&1.host))
    end

    test "a source nobody can have sent is no source" do
      long = String.duplicate("x", 200) <> ".example"

      assert :counted = Stats.count(view(%{referrer: "https://#{long}/a"}))
      assert Repo.one!(Texttile.Stats.View).referrer_host == nil
    end

    test "a reader who arrived direct is a source of their own" do
      seed_views(3)
      seed_views(1, path: "/blog", referrer_host: "lobste.rs")

      assert [direct, lobsters] = Stats.referrers(Stats.window(30))
      assert direct == %{host: nil, views: 3, share: 75}
      assert lobsters == %{host: "lobste.rs", views: 1, share: 25}
    end
  end

  describe "the numbers of one entry" do
    setup do
      %{article: published_post(%{title: "Concrete flowers"})}
    end

    test "views count for all time, and the series for the window", %{article: article} do
      seed_views(4, article_id: article.id, day: Date.add(Date.utc_today(), -30))
      seed_views(2, article_id: article.id)
      seed_views(9)

      assert Stats.article_views(article.id) == 6

      series = Stats.series(Stats.window(14), article_id: article.id)
      assert length(series) == 14
      assert List.last(series).views == 2
      assert Enum.sum(Enum.map(series, & &1.views)) == 2
    end

    test "referrers are the entry's own", %{article: article} do
      seed_views(2, article_id: article.id, referrer_host: "lobste.rs")
      seed_views(8, path: "/blog", referrer_host: "news.ycombinator.com")

      assert [%{host: "lobste.rs", views: 2, share: 100}] =
               Stats.referrers(Stats.window(30), article_id: article.id)
    end

    test "an entry counts for the whole blog too", %{article: article} do
      seed_views(2, article_id: article.id)

      assert Stats.summary(Stats.window(30)).views == 2
    end
  end
end
