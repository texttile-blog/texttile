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

  test "narrows the list to one year, then to one month of it", %{conn: conn} do
    # no year open, no months row
    refute conn |> get(~p"/blog") |> html_response(200) =~ ~s(id="months")

    html = conn |> get(~p"/blog?y=2026") |> html_response(200)

    assert html =~ "Harbour mornings"
    assert html =~ "Desert nights"
    refute html =~ "The long winter"

    assert html =~ ~s(id="months")
    assert html =~ ~s(href="/blog?y=2026&amp;m=3")
    assert html =~ ~s(href="/blog?y=2026&amp;m=8")
    # nobody wrote in the other ten months, so they are not a choice
    refute html =~ ~s(m=5")

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

  test "the mark of the open one goes on a year, never on All years", %{conn: conn} do
    # nothing chosen: All years is where the reader stands, and it says
    # so by being no way anywhere. It is not a choice, so it wears no
    # mark of one.
    html = conn |> get(~p"/blog") |> html_response(200)
    refute html =~ ~s(class="per on")

    # a year chosen: the year wears the mark, All years is the way back
    html = conn |> get(~p"/blog?y=2026") |> html_response(200)
    assert html =~ ~r/<span class="per on"[^>]*>\s*2026/
    assert html =~ ~s(href="/blog")
    refute html =~ ~r/class="per on"[^>]*>\s*All/
  end
end
