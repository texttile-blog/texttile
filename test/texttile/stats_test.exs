defmodule Texttile.StatsTest do
  use Texttile.DataCase

  import Texttile.ArticlesFixtures

  alias Texttile.Stats

  @agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
           "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"

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
      assert :counted = Stats.count(view())

      # An hour older than the window: the same person, a new visit.
      Repo.update_all(Texttile.Stats.View,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second)]
      )

      assert :counted = Stats.count(view())
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
      seed(article.id, Date.utc_today(), 3, "a")
      seed(article.id, Date.add(Date.utc_today(), -1), 5, "b")
      seed(article.id, Date.add(Date.utc_today(), -40), 9, "c")

      summary = Stats.summary(30)

      assert summary.views == 8
      assert summary.people == 8
      assert summary.busiest == {Date.add(Date.utc_today(), -1), 5}
    end

    test "a blog nobody read yet has a summary too" do
      assert Stats.summary(30) == %{views: 0, people: 0, busiest: nil}
    end

    test "by_day holds one number for every day of the window, oldest first" do
      seed(nil, Date.utc_today(), 2, "a")

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
      seed(article.id, Date.add(Date.utc_today(), -200), 4, "a")
      seed(other.id, Date.utc_today(), 7, "b")

      assert [first, second] = Stats.top_articles(10)

      assert first.article.id == other.id
      assert first.views == 7
      assert second.article.id == article.id
      assert second.views == 4
    end

    test "an entry nobody read is not in the table", %{article: article} do
      seed(article.id, Date.utc_today(), 1, "a")

      assert [row] = Stats.top_articles(10)
      assert row.article.id == article.id
    end

    test "the pages that are no entry are counted by address" do
      seed(nil, Date.utc_today(), 3, "a", "/blog")
      seed(nil, Date.utc_today(), 1, "b", "/tags/trains")

      assert [blog, tag] = Stats.other_pages(30)
      assert blog == %{path: "/blog", views: 3}
      assert tag == %{path: "/tags/trains", views: 1}
    end

    test "referrers carry their share of the window, biggest first" do
      seed(nil, Date.utc_today(), 3, "a", "/blog", "news.ycombinator.com")
      seed(nil, Date.utc_today(), 1, "b", "/blog", "lobste.rs")

      assert [hn, lobsters] = Stats.referrers(30)
      assert hn == %{host: "news.ycombinator.com", views: 3, share: 75}
      assert lobsters == %{host: "lobste.rs", views: 1, share: 25}
    end

    test "a reader who arrived direct is a source of their own" do
      seed(nil, Date.utc_today(), 3, "a")
      seed(nil, Date.utc_today(), 1, "b", "/blog", "lobste.rs")

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
      seed(article.id, Date.add(Date.utc_today(), -30), 4, "a")
      seed(article.id, Date.utc_today(), 2, "b")
      seed(nil, Date.utc_today(), 9, "c")

      assert Stats.article_views(article.id) == 6

      days = Stats.by_day(14, article_id: article.id)
      assert length(days) == 14
      assert List.last(days) == %{day: Date.utc_today(), views: 2}
      assert Enum.sum(Enum.map(days, & &1.views)) == 2
    end

    test "referrers are the entry's own", %{article: article} do
      seed(article.id, Date.utc_today(), 2, "a", "/x", "lobste.rs")
      seed(nil, Date.utc_today(), 8, "b", "/blog", "news.ycombinator.com")

      assert [%{host: "lobste.rs", views: 2, share: 100}] =
               Stats.referrers(30, article_id: article.id)
    end

    test "an entry counts for the whole blog too", %{article: article} do
      seed(article.id, Date.utc_today(), 2, "a")

      assert Stats.summary(30).views == 2
    end
  end

  # Views straight into the table: the reports are what is under test
  # here, not the way in.
  defp seed(article_id, day, count, tag, path \\ "/x", referrer_host \\ nil) do
    at = DateTime.new!(day, ~T[12:00:00], "Etc/UTC")

    for n <- 1..count do
      Repo.insert!(%Stats.View{
        day: day,
        path: path,
        article_id: article_id,
        visitor: "#{tag}#{n}",
        referrer_host: referrer_host,
        inserted_at: at
      })
    end
  end
end
