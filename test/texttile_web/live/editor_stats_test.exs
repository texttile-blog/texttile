defmodule TexttileWeb.EditorStatsTest do
  @moduledoc """
  The Stats tab of one entry in the editor.
  """
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Repo
  alias Texttile.Stats

  setup :register_and_log_in_user

  defp seed(article_id, day, count, tag, referrer_host \\ nil) do
    for n <- 1..count do
      Repo.insert!(%Stats.View{
        day: day,
        path: "/x",
        article_id: article_id,
        visitor: "#{tag}#{n}",
        referrer_host: referrer_host,
        inserted_at: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")
      })
    end
  end

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
    seed(article.id, Date.utc_today(), 5, "a")

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")

    assert has_element?(view, "#tpFigViews", "5")
    assert has_element?(view, "#tp-stats", "views since 2026-07-01")
    assert has_element?(view, "#tpFigComments", "0")
    assert has_element?(view, "#tpFigTiles", "0")
  end

  test "views of all time count, the chart only shows the last 14 days", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    seed(article.id, Date.add(Date.utc_today(), -100), 4, "a")
    seed(article.id, Date.utc_today(), 2, "b")

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=stats")

    assert has_element?(view, "#tpFigViews", "6")

    chart = view |> element("#tpDayChart") |> render()
    assert chart |> String.split("<i ") |> length() == 15
  end

  test "the referrers are the entry's own", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})
    other = published_post(%{title: "Slow trains"})
    seed(article.id, Date.utc_today(), 2, "a", "lobste.rs")
    seed(other.id, Date.utc_today(), 8, "b", "news.ycombinator.com")

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

  test "a scheduled entry says when the numbers start", %{conn: conn} do
    scheduled = scheduled_post(%{title: "Winter light", publish_date: ~D[2099-01-20]})

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{scheduled.id}?tab=stats")

    assert has_element?(view, "#tpStatsEmpty", "2099-01-20")
  end
end
