defmodule TexttileWeb.EditorStatsTest do
  @moduledoc """
  The Stats tab of one entry in the editor.
  """
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures
  import Texttile.StatsFixtures

  setup :register_and_log_in_user

  test "the tab stands beside the others and the address opens it", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}")
    assert has_element?(view, ~s(button[phx-value-tab="stats"]), "Stats")

    view |> element(~s(button[phx-value-tab="stats"])) |> render_click()
    assert has_element?(view, "#tp-stats")

    {:ok, direct, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")
    assert has_element?(direct, "#tp-stats")
  end

  test "a published entry shows its views, comments and images", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers", publish_date: ~D[2026-07-01]})
    seed_views(5, article_id: article.id)

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")

    assert has_element?(view, "#tpFigViews", "5")
    assert has_element?(view, "#tp-stats", "views since 2026-07-01")
    assert has_element?(view, "#tpFigComments", "0")
    assert has_element?(view, "#tpFigTiles", "0")
  end

  test "views of all time count, the chart only shows the last 14 days", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed_views(4, article_id: article.id, day: Date.add(Date.utc_today(), -100))
    seed_views(2, article_id: article.id)

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")

    assert has_element?(view, "#tpFigViews", "6")

    chart = view |> element("#tpDayChart") |> render()
    assert chart |> String.split("<i ") |> length() == 15
  end

  test "an entry nobody has read yet shows a line, not an empty chart", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")

    assert has_element?(view, "#tpFigViews", "0")
    assert has_element?(view, "#tpDayChartEmpty")
    refute has_element?(view, "#tpDayChart")
  end

  test "the referrers are the entry's own", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    other = published_post(%{title: "Slow trains"})
    seed_views(2, article_id: article.id, referrer_host: "lobste.rs")
    seed_views(8, article_id: other.id, referrer_host: "news.ycombinator.com")

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")

    assert has_element?(view, "#tpReferrers", "lobste.rs")
    refute has_element?(view, "#tpReferrers", "news.ycombinator.com")
  end

  test "a draft says why there is nothing to show", %{conn: conn} do
    draft = draft_post(%{title: "Fog over the harbor"})

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{draft.id}?tab=stats")

    assert has_element?(view, "#tpStatsEmpty", "Drafts are invisible to readers")
    refute has_element?(view, "#tpDayChart")
  end

  test "publishing while the tab is open fills it, unpublishing empties it", %{conn: conn} do
    draft = draft_post(%{title: "Fog over the harbor"})

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{draft.id}?tab=stats")
    assert has_element?(view, "#tpStatsEmpty")

    view |> element("button", "Publish") |> render_click()

    # The panel must never be blank, and never say "no numbers yet"
    # over a row of them.
    assert has_element?(view, "#tpFigViews")
    refute has_element?(view, "#tpStatsEmpty")

    view |> element("#stateBtn [aria-haspopup]") |> render_click()
    view |> element("#stateMenu button", "Unpublish") |> render_click()

    assert has_element?(view, "#tpStatsEmpty")
    refute has_element?(view, "#tpFigViews")
  end

  test "another admin unpublishing the entry empties the open tab", %{conn: conn, user: user} do
    article = published_post(%{title: "Concrete flowers", user: user})
    seed_views(3, article_id: article.id)

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")
    assert has_element?(view, "#tpFigViews", "3")

    {:ok, _} = Texttile.Articles.unpublish(article, user)

    assert has_element?(view, "#tpStatsEmpty")
    refute has_element?(view, "#tpFigViews")
  end

  test "a scheduled entry says when the numbers start", %{conn: conn} do
    scheduled = scheduled_post(%{title: "Winter light", publish_date: ~D[2099-01-20]})

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{scheduled.id}?tab=stats")

    assert has_element?(view, "#tpStatsEmpty", "2099-01-20")
  end
end
