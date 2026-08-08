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
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures
  import TexttileWeb.E2E, only: [sign_in: 1, open: 2]

  alias Texttile.Repo
  alias Texttile.Stats

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

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

  test "a reader's page reports itself, an admin's does not", %{conn: conn} do
    user_fixture(%{username: "kb"})
    article = published_post(%{title: "Concrete flowers of Kaunas"})

    # The reader: the list and the entry both carry the beacon, and the
    # entry names itself in it.
    conn
    |> visit("/blog")
    |> assert_has("body[data-count]")
    |> click_link("Concrete flowers of Kaunas")
    |> assert_has("body[data-count][data-count-entry='#{article.id}']")

    # The same entry with an admin reading it: nothing to report.
    conn
    |> sign_in()
    |> visit(Texttile.Articles.public_path(article))
    |> refute_has("body[data-count]")
  end

  test "the admin reads the numbers on Stats and follows one entry into the editor",
       %{conn: conn} do
    user_fixture(%{username: "kb"})
    article = published_post(%{title: "Concrete flowers of Kaunas"})

    seed(article.id, Date.utc_today(), 7, "a", "/x", "news.ycombinator.com")
    seed(article.id, Date.add(Date.utc_today(), -1), 3, "b")
    seed(nil, Date.utc_today(), 2, "c", "/blog")

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
    user_fixture(%{username: "kb"})
    draft = draft_post(%{title: "Fog over the harbor"})

    conn
    |> sign_in()
    |> open("/admin/texts/#{draft.id}?tab=stats")
    |> assert_has("#tpStatsEmpty", text: "Drafts are invisible to readers")
  end
end
