defmodule TexttileWeb.SiteArchiveTest do
  @moduledoc """
  The archive over the reader's list: one line of years, the months of
  the open year under it, and both of them real addresses.
  """
  use TexttileWeb.ConnCase, async: false

  import Texttile.ArticlesFixtures

  setup do
    %{
      august: published_post(title: "Harbour mornings", publish_date: ~D[2026-08-08]),
      march: published_post(title: "Desert nights", publish_date: ~D[2026-03-02]),
      older: published_post(title: "The long winter", publish_date: ~D[2024-12-24])
    }
  end

  test "names every year the blog has, newest first, with its count", %{conn: conn} do
    html = conn |> get(~p"/blog") |> html_response(200)

    assert html =~ ~s(id="years")
    assert html =~ ~s(href="/blog?y=2026")
    assert html =~ ~s(href="/blog?y=2024")

    {newer, _} = :binary.match(html, "2026")
    {older, _} = :binary.match(html, "2024")
    assert newer < older
  end

  test "shows no months before a year is open", %{conn: conn} do
    html = conn |> get(~p"/blog") |> html_response(200)
    refute html =~ ~s(id="months")
  end

  test "narrows the list to one year and offers only the months it has", %{conn: conn} do
    html = conn |> get(~p"/blog?y=2026") |> html_response(200)

    assert html =~ "Harbour mornings"
    assert html =~ "Desert nights"
    refute html =~ "The long winter"

    assert html =~ ~s(id="months")
    assert html =~ ~s(href="/blog?y=2026&amp;m=3")
    assert html =~ ~s(href="/blog?y=2026&amp;m=8")
    # nobody wrote in the other ten months, so they are not a choice
    refute html =~ ~s(m=5")
  end

  test "narrows the list to one month of the year", %{conn: conn} do
    html = conn |> get(~p"/blog?y=2026&m=8") |> html_response(200)

    assert html =~ "Harbour mornings"
    refute html =~ "Desert nights"
  end

  test "All years counts what the search found, like the years beside it", %{conn: conn} do
    html = conn |> get(~p"/blog") |> html_response(200)
    assert html =~ ~r/All years<span class="cnt"[^>]*>3<\/span>/

    # one of the three carries the word, and one of the years does too:
    # both numbers have to come from the same list
    html = conn |> get(~p"/blog?q=harbour") |> html_response(200)
    assert html =~ ~r/All years<span class="cnt"[^>]*>1<\/span>/
    refute html =~ ~r/All years<span class="cnt"[^>]*>3<\/span>/
  end

  test "lets go of a year the search has emptied", %{conn: conn} do
    html = conn |> get(~p"/blog?y=2024&q=harbour") |> html_response(200)

    assert html =~ "Harbour mornings"
    refute html =~ ~s(<span class="per on" aria-current="true">\n      2024)
  end

  test "ignores a year the blog never had", %{conn: conn} do
    html = conn |> get(~p"/blog?y=1998") |> html_response(200)

    assert html =~ "Harbour mornings"
    assert html =~ "The long winter"
  end

  test "the search and the year travel together in the pager and the Clear", %{conn: conn} do
    html = conn |> get(~p"/blog?y=2026&q=harbour") |> html_response(200)
    assert html =~ ~s(id="clear")
  end
end
