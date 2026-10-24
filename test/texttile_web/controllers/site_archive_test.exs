defmodule TexttileWeb.SiteArchiveTest do
  @moduledoc """
  The archive under the reader's list: the year and the month as
  choices on the search form, and the line under the heading that
  says what narrowed the list.
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

  test "offers every year the blog has, newest first, with its count", %{conn: conn} do
    html = conn |> get(~p"/blog") |> html_response(200)

    assert html =~ ~s(id="year")
    assert html =~ ~r/<option value="2026"[^>]*>\s*2026 \(2\)/
    assert html =~ ~r/<option value="2024"[^>]*>\s*2024 \(1\)/

    {newer, _} = :binary.match(html, ~s(value="2026"))
    {older, _} = :binary.match(html, ~s(value="2024"))
    assert newer < older

    # the archive stands under the list, not over it
    {list, _} = :binary.match(html, ~s(id="texts"))
    {archive, _} = :binary.match(html, ~s(id="archive"))
    assert list < archive
  end

  test "narrows the list to one year, then to one month of it", %{conn: conn} do
    # no year open, no month to choose
    refute conn |> get(~p"/blog") |> html_response(200) =~ ~s(id="month")

    html = conn |> get(~p"/blog?y=2026") |> html_response(200)

    assert html =~ "Harbour mornings"
    assert html =~ "Desert nights"
    refute html =~ "The long winter"

    assert html =~ ~r/<option value="2026"[^>]*selected/
    assert html =~ ~s(id="month")
    assert html =~ ~s(<option value="3")
    assert html =~ ~s(<option value="8")
    # nobody wrote in the other ten months, so they are not a choice
    refute html =~ ~s(<option value="5")

    html = conn |> get(~p"/blog?y=2026&m=8") |> html_response(200)

    assert html =~ "Harbour mornings"
    refute html =~ "Desert nights"
    assert html =~ ~r/<option value="8"[^>]*selected/
  end

  test "the counts in the choices follow the search", %{conn: conn} do
    # one of the three carries the word, and one of the years does too:
    # both numbers have to come from the same list
    html = conn |> get(~p"/blog?q=harbour") |> html_response(200)
    assert html =~ ~r/<option value="2026"[^>]*>\s*2026 \(1\)/
    refute html =~ "2024 ("
  end

  test "says under the heading what narrowed the list, and the way back", %{conn: conn} do
    refute conn |> get(~p"/blog") |> html_response(200) =~ ~s(id="narrowed")

    html = conn |> get(~p"/blog?y=2026") |> html_response(200)
    assert html =~ "Entries from 2026."
    assert html =~ ~r/id="narrowed".*href="\/blog"/s

    html = conn |> get(~p"/blog?y=2026&m=8") |> html_response(200)
    assert html =~ "Entries from August 2026."

    html = conn |> get(~p"/blog?q=harbour") |> html_response(200)
    assert html =~ "Entries matching “harbour”."

    html = conn |> get(~p"/blog?q=harbour&y=2026") |> html_response(200)
    assert html =~ "Entries matching “harbour” from 2026."
  end
end
