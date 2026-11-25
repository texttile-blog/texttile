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
    |> assert_has(by_css("body[data-count]"))
    |> click(by_role(:link, name: "Concrete flowers of Kaunas"))
    |> assert_has(by_css("body[data-count][data-count-entry='#{article.id}']"))

    # The same entry with an admin reading it: nothing to report.
    conn
    |> sign_in()
    |> open_page(Texttile.Articles.public_path(article))
    |> refute_has(by_css("body[data-count]"))
  end

  test "the admin reads the numbers on Stats and follows one entry into the editor",
       %{conn: conn} do
    article = published_post(%{title: "Concrete flowers of Kaunas"})

    seed_views(7, article_id: article.id, referrer_host: "news.ycombinator.com")
    seed_views(3, article_id: article.id, day: Date.add(Date.utc_today(), -1))
    seed_views(2, path: "/blog")

    conn
    |> sign_in()
    |> click(by_css("#wmBtn"))
    |> click(by_css("#navMenu a[data-key='8']") |> filter(has_text: "Stats"))
    |> assert(contain_text(by_css("h1"), "Stats"))
    |> assert(contain_text(by_css("#figViews"), "12"))
    |> assert(contain_text(by_css("#figPeople"), "12"))
    |> assert(contain_text(by_css("#figBusiest"), "9"))
    |> assert_has(by_css("#dayChart"))
    |> assert(contain_text(by_css("#top-#{article.id}"), "Concrete flowers of Kaunas"))
    |> assert(contain_text(by_css("#referrers"), "news.ycombinator.com"))
    |> assert(contain_text(by_css("#otherPages"), "/blog"))
    # A bar opens the day under the chart, the address remembers it,
    # and the window switch is a link that keeps the page live.
    |> click(by_css("#bar-#{Date.utc_today()}"))
    |> assert(contain_text(by_css("#barTitle"), "9 views"))
    |> assert(contain_text(by_css("#barPages"), "Concrete flowers of Kaunas"))
    |> assert(contain_text(by_css("#barPages"), "/blog"))
    |> assert(
      page_url(fn url ->
        url.path == "/admin/stats" and
          URI.decode_query(url.query || "") == %{
            "days" => "30",
            "day" => Date.to_iso8601(Date.utc_today())
          }
      end)
    )
    |> click(by_css("#win-7"))
    |> assert_has(by_css("#win-7.on"))
    |> assert(contain_text(by_css("#figViews"), "12"))
    |> refute_has(by_css("#barDetail"))
    |> click(by_css("#top-#{article.id} a") |> filter(has_text: "Concrete flowers of Kaunas"))
    |> assert_has(by_css("#tp-stats"))
    |> assert(contain_text(by_css("#tpFigViews"), "10"))
    |> assert(contain_text(by_css("#tpReferrers"), "news.ycombinator.com"))
  end

  test "a draft says why its Stats tab is empty", %{conn: conn} do
    draft = draft_post(%{title: "Fog over the harbor"})

    conn
    |> sign_in()
    |> open("/admin/texts/#{draft.id}?tab=stats")
    |> assert(contain_text(by_css("#tpStatsEmpty"), "Drafts are invisible to readers"))
  end
end
