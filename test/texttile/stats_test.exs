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
      assert Stats.summary(30).views == 1
    end

    test "the same person on the same page counts once for half an hour" do
      assert :counted = Stats.count(view())
      assert {:dropped, :repeat} = Stats.count(view())
      assert Stats.summary(30).views == 1
    end

    test "the same person on another page counts again" do
      assert :counted = Stats.count(view())
      assert :counted = Stats.count(view(%{path: "/2026/08/08/a-text"}))
      assert Stats.summary(30).views == 2
    end

    test "a repeat after the window counts again" do
      now = DateTime.utc_now(:second)
      assert :counted = Stats.count(view(), now: now)

      # An hour on, past the window: the same person, a new visit.
      assert :counted = Stats.count(view(), now: DateTime.add(now, 3600, :second))
      assert Stats.summary(30).views == 2
    end

    test "two addresses are two people, one address is one" do
      assert :counted = Stats.count(view(%{ip: "203.0.113.9"}))
      assert :counted = Stats.count(view(%{ip: "198.51.100.4", path: "/blog"}))

      assert Stats.summary(30).people == 2
    end

    test "the same address in another browser is another person" do
      assert :counted = Stats.count(view())
      assert :counted = Stats.count(view(%{user_agent: @agent <> " Firefox/128.0"}))

      assert Stats.summary(30).people == 2
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

      assert Stats.summary(30).views == 0
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

    test "summary counts views, people and the busiest day", %{article: article} do
      seed_views(3, article_id: article.id)
      seed_views(5, article_id: article.id, day: Date.add(Date.utc_today(), -1))
      seed_views(9, article_id: article.id, day: Date.add(Date.utc_today(), -40))

      summary = Stats.summary(30)

      assert summary.views == 8
      assert summary.people == 8
      assert summary.busiest == {Date.add(Date.utc_today(), -1), 5}
    end

    test "a blog nobody read yet has a summary too" do
      assert Stats.summary(30) == %{views: 0, people: 0, busiest: nil}
    end

    test "by_day holds one number for every day of the window, oldest first" do
      seed_views(2)

      days = Stats.by_day(30)

      assert length(days) == 30
      assert List.first(days).day == Date.add(Date.utc_today(), -29)
      assert List.last(days) == %{day: Date.utc_today(), views: 2}
      assert Enum.at(days, 28) == %{day: Date.add(Date.utc_today(), -1), views: 0}
    end

    test "top entries are counted for all time, most read first", %{
      article: article,
      other: other
    } do
      seed_views(4, article_id: article.id, day: Date.add(Date.utc_today(), -200))
      seed_views(7, article_id: other.id)

      assert [first, second] = Stats.top_articles(10)

      assert first.article.id == other.id
      assert first.views == 7
      assert second.article.id == article.id
      assert second.views == 4
    end

    test "an entry nobody read is not in the table", %{article: article} do
      seed_views(1, article_id: article.id)

      assert [row] = Stats.top_articles(10)
      assert row.article.id == article.id
    end

    test "the pages that are no entry are counted by address" do
      seed_views(3, path: "/blog")
      seed_views(1, path: "/tags/trains")

      assert [blog, tag] = Stats.other_pages(30)
      assert blog == %{path: "/blog", views: 3}
      assert tag == %{path: "/tags/trains", views: 1}
    end

    test "referrers carry their share of the window, biggest first" do
      seed_views(3, path: "/blog", referrer_host: "news.ycombinator.com")
      seed_views(1, path: "/blog", referrer_host: "lobste.rs")

      assert [hn, lobsters] = Stats.referrers(30)
      assert hn == %{host: "news.ycombinator.com", views: 3, share: 75}
      assert lobsters == %{host: "lobste.rs", views: 1, share: 25}
    end

    test "the tables hold a bounded number of rows, whatever a caller writes" do
      # The address and the source come from the caller, so the number
      # of different ones is theirs to choose. The screen's is not.
      for n <- 1..(Stats.rows() + 5) do
        seed_views(1, path: "/made-up-#{n}", referrer_host: "host#{n}.example")
      end

      assert length(Stats.other_pages(30)) == Stats.rows()
      assert length(Stats.referrers(30)) == Stats.rows()
    end

    test "a share is of every view of the window, not of the rows shown" do
      seed_views(1, path: "/blog", referrer_host: "lobste.rs")
      seed_views(3, path: "/blog")

      assert %{host: nil, views: 3, share: 75} = Enum.find(Stats.referrers(30), &is_nil(&1.host))
    end

    test "a source nobody can have sent is no source" do
      long = String.duplicate("x", 200) <> ".example"

      assert :counted = Stats.count(view(%{referrer: "https://#{long}/a"}))
      assert Repo.one!(Texttile.Stats.View).referrer_host == nil
    end

    test "a reader who arrived direct is a source of their own" do
      seed_views(3)
      seed_views(1, path: "/blog", referrer_host: "lobste.rs")

      assert [direct, lobsters] = Stats.referrers(30)
      assert direct == %{host: nil, views: 3, share: 75}
      assert lobsters == %{host: "lobste.rs", views: 1, share: 25}
    end
  end

  describe "the numbers of one entry" do
    setup do
      %{article: published_post(%{title: "Concrete flowers"})}
    end

    test "views count for all time, and the day row for the window", %{article: article} do
      seed_views(4, article_id: article.id, day: Date.add(Date.utc_today(), -30))
      seed_views(2, article_id: article.id)
      seed_views(9)

      assert Stats.article_views(article.id) == 6

      days = Stats.by_day(14, article_id: article.id)
      assert length(days) == 14
      assert List.last(days) == %{day: Date.utc_today(), views: 2}
      assert Enum.sum(Enum.map(days, & &1.views)) == 2
    end

    test "referrers are the entry's own", %{article: article} do
      seed_views(2, article_id: article.id, referrer_host: "lobste.rs")
      seed_views(8, path: "/blog", referrer_host: "news.ycombinator.com")

      assert [%{host: "lobste.rs", views: 2, share: 100}] =
               Stats.referrers(30, article_id: article.id)
    end

    test "an entry counts for the whole blog too", %{article: article} do
      seed_views(2, article_id: article.id)

      assert Stats.summary(30).views == 2
    end
  end
end
