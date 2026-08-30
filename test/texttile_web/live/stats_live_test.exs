defmodule TexttileWeb.StatsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures
  import Texttile.StatsFixtures

  alias Texttile.Stats

  setup :register_and_log_in_user

  test "a blog nobody has read yet says so instead of showing nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#crumb", "Stats")
    assert has_element?(view, "#figViews", "0")
    assert has_element?(view, "#figBusiest", "0")
    assert has_element?(view, "#topEmpty")
    assert has_element?(view, "#referrersEmpty")
    assert has_element?(view, "#statsRule")

    # An empty chart is thirty flat stubs under an empty box: one line
    # says more, so the chart stays away until there is one bar.
    assert has_element?(view, "#dayChartEmpty")
    refute has_element?(view, "#dayChart")
  end

  test "the wordmark menu carries the entry with its key", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, ~s(#navMenu a[data-key="8"]), "Stats")
  end

  test "the figures count views, people and the busiest day", %{conn: conn} do
    seed_views(3)
    seed_views(5, day: Date.add(Date.utc_today(), -1))

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#figViews", "8")
    assert has_element?(view, "#figPeople", "8")
    assert has_element?(view, "#figBusiest", "5")
    assert render(view) =~ "busiest day,"
  end

  test "the chart holds one bar per day of the window", %{conn: conn} do
    seed_views(2)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    chart = view |> element("#dayChart") |> render()

    assert chart =~ "height:100%"
    assert chart |> String.split("<button ") |> length() == 31
  end

  test "the top table names the entries and jumps into their Stats tab", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed_views(4, article_id: article.id)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#top-#{article.id}", "Concrete flowers")

    assert has_element?(
             view,
             ~s(#top-#{article.id} a[href="/admin/texts/#{article.id}?tab=stats"])
           )
  end

  test "the referrer table names the sources and calls the rest direct", %{conn: conn} do
    seed_views(3, path: "/blog", referrer_host: "lobste.rs")
    seed_views(1, path: "/blog")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#referrers", "lobste.rs")
    assert has_element?(view, "#referrers", "direct")
    assert view |> element("#referrers") |> render() =~ "width:75%"
  end

  test "the pages that are no entry are listed by address", %{conn: conn} do
    seed_views(3, path: "/blog")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#otherPages", "/blog")
  end

  test "an entry's own views are not in the list of other pages", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed_views(2, article_id: article.id, path: "/2026/08/08/concrete-flowers")

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    refute has_element?(view, "#otherPages")
  end

  test "a full table says it is full, so no cap is silent", %{conn: conn} do
    for n <- 1..(Stats.rows() + 3) do
      seed_views(1, path: "/made-up-#{n}", referrer_host: "host#{n}.example")
    end

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#referrersCapped")
    assert has_element?(view, "#pagesCapped")
  end

  test "a big number is written with a space between the thousands", %{conn: conn} do
    seed_views(1200)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#figViews", "1 200")
  end

  test "a day older than the window is not counted", %{conn: conn} do
    seed_views(9, day: Date.add(Date.utc_today(), -40))

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#figViews", "0")
  end

  test "the window is picked in the URL, and the chart and the figures follow", %{conn: conn} do
    seed_views(1, day: Date.add(Date.utc_today(), -45))

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=90")

    assert has_element?(view, "#win-90.on")
    assert has_element?(view, "#figViews", "1")
    assert render(view) =~ "views, last 90 days"

    # Ninety days are thirteen or fourteen weeks, not ninety bars.
    bars = view |> element("#dayChart") |> render() |> String.split("<button ") |> length()
    assert bars in [14, 15]

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=30")
    assert has_element?(view, "#win-30.on")
    assert has_element?(view, "#figViews", "0")

    # A window that is none is the usual one, a number or not.
    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=forever")
    assert has_element?(view, "#win-30.on")

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=45")
    assert has_element?(view, "#win-30.on")
  end

  test "a bar that is no day says so, and a month axis carries the year", %{conn: conn} do
    seed_views(1, day: Date.add(Date.utc_today(), -45))

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=90")
    assert render(view) =~ "Views, last 90 days, by week"

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=365")
    assert render(view) =~ "Views, last 365 days, by month"

    assert view |> element("#dayChart + div") |> render() =~
             Integer.to_string(Date.utc_today().year)

    # A fresh blog with one month of views is a month bar too.
    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=all")
    assert render(view) =~ "Views, all time, by month"

    assert view |> element("#dayChart + div") |> render() =~
             Integer.to_string(Date.utc_today().year)
  end

  test "a clicked bar opens what was read under the chart, and the URL remembers it", %{
    conn: conn
  } do
    article = published_post(%{title: "Concrete flowers"})
    today = Date.utc_today()
    seed_views(3, article_id: article.id, path: "/x", referrer_host: "lobste.rs")
    seed_views(2, path: "/blog", day: Date.add(today, -1))

    {:ok, view, _html} = live(conn, ~p"/admin/stats")
    refute has_element?(view, "#barDetail")

    view |> element("#bar-#{today}") |> render_click()

    assert_patch(view, "/admin/stats?days=30&day=#{today}")
    assert has_element?(view, "#bar-#{today}.on")
    assert has_element?(view, "#barDetail")
    assert has_element?(view, "#barTitle", "3 views")
    assert has_element?(view, "#barPages", "Concrete flowers")
    refute has_element?(view, "#barPages", "/blog")
    assert has_element?(view, "#barReferrers", "lobste.rs")

    # The bar again, or the link, closes it.
    view |> element("#barClose") |> render_click()
    assert_patch(view, ~p"/admin/stats?days=30")
    refute has_element?(view, "#barDetail")

    # Straight from the address, the day is open already.
    {:ok, view, _html} = live(conn, "/admin/stats?days=30&day=#{Date.add(today, -1)}")
    assert has_element?(view, "#barPages", "/blog")
    assert has_element?(view, "#barPages", "2")
  end

  test "a day outside the window opens nothing", %{conn: conn} do
    seed_views(1)

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=7&day=2020-01-01")
    refute has_element?(view, "#barDetail")

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=7&day=not-a-day")
    refute has_element?(view, "#barDetail")
  end

  test "the figures say how the window moved against the one before", %{conn: conn} do
    seed_views(3)
    seed_views(2, day: Date.add(Date.utc_today(), -35))

    {:ok, view, _html} = live(conn, ~p"/admin/stats")
    assert view |> element("#statsFigures") |> render() =~ ~r{\+50\s%}u

    # Fewer than before is written with its sign too.
    seed_views(4, day: Date.add(Date.utc_today(), -35))
    {:ok, view, _html} = live(conn, ~p"/admin/stats")
    assert view |> element("#statsFigures") |> render() =~ ~r{-50\s%}u

    # All time has nothing to move against.
    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=all")
    refute view |> element("#statsFigures") |> render() =~ "%"
  end

  test "the top table counts the window, with the people beside the views", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed_views(4, article_id: article.id, day: Date.add(Date.utc_today(), -200))

    {:ok, view, _html} = live(conn, ~p"/admin/stats")
    refute has_element?(view, "#top-#{article.id}")

    {:ok, view, _html} = live(conn, ~p"/admin/stats?days=all")
    assert has_element?(view, "#top-#{article.id} .people", "4")
  end
end
