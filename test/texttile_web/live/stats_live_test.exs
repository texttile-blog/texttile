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
    assert chart |> String.split("<i ") |> length() == 31
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
end
