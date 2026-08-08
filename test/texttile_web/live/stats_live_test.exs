defmodule TexttileWeb.StatsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Repo
  alias Texttile.Stats

  setup :register_and_log_in_user

  # Views straight into the table: the screen is what is under test.
  defp seed(article_id, day, count, tag, path \\ "/x", referrer_host \\ nil) do
    for n <- 1..count do
      Repo.insert!(%Stats.View{
        day: day,
        path: path,
        article_id: article_id,
        visitor: "#{tag}#{n}",
        referrer_host: referrer_host,
        inserted_at: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")
      })
    end
  end

  test "a blog nobody has read yet says so instead of showing nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#crumb", "Stats")
    assert has_element?(view, "#figViews", "0")
    assert has_element?(view, "#figBusiest", "0")
    assert has_element?(view, "#topEmpty")
    assert has_element?(view, "#referrersEmpty")
    assert has_element?(view, "#statsRule")
  end

  test "the wordmark menu carries the entry with its key", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, ~s(#navMenu a[data-key="8"]), "Stats")
  end

  test "the figures count views, people and the busiest day", %{conn: conn} do
    seed(nil, Date.utc_today(), 3, "a")
    seed(nil, Date.add(Date.utc_today(), -1), 5, "b")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#figViews", "8")
    assert has_element?(view, "#figPeople", "8")
    assert has_element?(view, "#figBusiest", "5")
    assert render(view) =~ "busiest day,"
  end

  test "the chart holds one bar per day of the window", %{conn: conn} do
    seed(nil, Date.utc_today(), 2, "a")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    chart = view |> element("#dayChart") |> render()

    assert chart =~ "height:100%"
    assert chart |> String.split("<i ") |> length() == 31
  end

  test "the top table names the entries and jumps into their Stats tab", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed(article.id, Date.utc_today(), 4, "a")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#top-#{article.id}", "Concrete flowers")

    assert has_element?(
             view,
             ~s(#top-#{article.id} a[href="/admin/texts/#{article.id}?tab=stats"])
           )
  end

  test "the referrer table names the sources and calls the rest direct", %{conn: conn} do
    seed(nil, Date.utc_today(), 3, "a", "/blog", "lobste.rs")
    seed(nil, Date.utc_today(), 1, "b", "/blog")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#referrers", "lobste.rs")
    assert has_element?(view, "#referrers", "direct")
    assert view |> element("#referrers") |> render() =~ "width:75%"
  end

  test "the pages that are no entry are listed by address", %{conn: conn} do
    seed(nil, Date.utc_today(), 3, "a", "/blog")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#otherPages", "/blog")
  end

  test "an entry's own views are not in the list of other pages", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed(article.id, Date.utc_today(), 2, "a", "/2026/08/08/concrete-flowers")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    refute has_element?(view, "#otherPages")
  end

  test "a day older than the window is not counted", %{conn: conn} do
    seed(nil, Date.add(Date.utc_today(), -40), 9, "a")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#figViews", "0")
  end
end
