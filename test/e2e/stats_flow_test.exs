defmodule TexttileWeb.E2E.StatsFlowTest do
  @moduledoc """
  The Stats feature through the real UI: what a reader page tells the
  counter, and what the two screens make of the numbers.

  The counting itself is driven through `Texttile.Stats.count/1` here,
  not through the browser. A browser test wears the sandbox metadata
  as its browser line, which is a fresh random string per run: the bot
  filter would read it anew every time, and a test must not depend on
  that. What the browser is asked here is what only it can answer -
  whether the page carries the beacon at all. The way from the request
  to the row is `TexttileWeb.StatsBeaconTest`.
  """
  use TexttileWeb.E2E

  import Texttile.StatsFixtures

  test "a reader's page reports itself, an admin's does not", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers of Kaunas"})

    # The reader: the list and the entry both carry the beacon, and the
    # entry names itself in it.
    conn
    |> open_page("/blog")
    |> assert_has("body[data-count]")
    |> click_link("Concrete flowers of Kaunas")
    |> assert_has("body[data-count][data-count-entry='#{article.id}']")

    # The same entry with an admin reading it: nothing to report.
    conn
    |> sign_in()
    |> open_page(Texttile.Articles.public_path(article))
    |> refute_has("body[data-count]")
  end

  test "the admin reads the numbers on Stats and follows one entry into the editor",
       %{conn: conn} do
    article = published_post(%{title: "Concrete flowers of Kaunas"})

    seed_views(7, article_id: article.id, referrer_host: "news.ycombinator.com")
    seed_views(3, article_id: article.id, day: Date.add(Date.utc_today(), -1))
    seed_views(2, path: "/blog")

    conn
    |> sign_in()
    |> click_button("#wmBtn", "Texttile")
    |> click_link("#navMenu a[data-key='8']", "Stats")
    |> assert_has("h1", text: "Stats")
    |> assert_has("#figViews", text: "12")
    |> assert_has("#figPeople", text: "12")
    |> assert_has("#figBusiest", text: "9")
    |> assert_has("#dayChart")
    |> assert_has("#top-#{article.id}", text: "Concrete flowers of Kaunas")
    |> assert_has("#referrers", text: "news.ycombinator.com")
    |> assert_has("#otherPages", text: "/blog")
    |> click_link("#top-#{article.id} a", "details")
    |> assert_has("#tp-stats")
    |> assert_has("#tpFigViews", text: "10")
    |> assert_has("#tpReferrers", text: "news.ycombinator.com")
  end

  test "a draft says why its Stats tab is empty", %{conn: conn} do
    draft = draft_post(%{title: "Fog over the harbor"})

    conn
    |> sign_in()
    |> open("/admin/texts/#{draft.id}?tab=stats")
    |> assert_has("#tpStatsEmpty", text: "Drafts are invisible to readers")
  end
end
