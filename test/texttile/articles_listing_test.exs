defmodule Texttile.ArticlesListingTest do
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles.Listing
  alias Texttile.Settings

  defp on(date), do: published_post(publish_date: date)

  describe "assemble/2" do
    test "an empty list is one empty page" do
      list = Listing.assemble([])

      assert list.entries == []
      assert list.page == 1
      assert list.pages == 1
      assert list.shown == 0
      assert list.across_years == 0
      assert {list.year, list.month} == {nil, nil}
    end

    test "cuts the list into pages of the installation's size" do
      Settings.put(:posts_per_page, 2)
      articles = for day <- 1..5, do: on(Date.new!(2026, 3, day))
      newest_first = Enum.reverse(articles)

      list = Listing.assemble(newest_first)
      assert list.pages == 3
      assert length(list.entries) == 2
      assert list.shown == 5

      last = Listing.assemble(newest_first, page: 3)
      assert last.page == 3
      assert length(last.entries) == 1
    end

    test "a page outside the row lands on the last page, not on an error" do
      Settings.put(:posts_per_page, 2)
      found = for day <- 1..3, do: on(Date.new!(2026, 3, day))

      assert Listing.assemble(found, page: 99).page == 2
      assert Listing.assemble(found, page: "99").page == 2
    end

    test "the page arrives as the address writes it, and nonsense means the first page" do
      found = [on(~D[2026-03-01])]

      assert Listing.assemble(found, page: "2").page == 1
      assert Listing.assemble(found, page: "x").page == 1
      assert Listing.assemble(found, page: nil).page == 1
      assert Listing.assemble(found, page: "-3").page == 1
    end

    test "narrows to a year and then to a month of it" do
      in_march = on(~D[2026-03-05])
      in_august = on(~D[2026-08-05])
      earlier = on(~D[2024-01-01])

      list = Listing.assemble([in_august, in_march, earlier], year: 2026, month: 3)

      assert Enum.map(list.entries, & &1.id) == [in_march.id]
      assert {list.year, list.month} == {2026, 3}
      assert list.years == [{2026, 2}, {2024, 1}]
      assert list.months == [{3, 1}, {8, 1}]
      assert list.shown == 1
      assert list.across_years == 3
    end

    test "the year and the month arrive as the address writes them" do
      list = Listing.assemble([on(~D[2026-08-08])], year: "2026", month: "8")

      assert {list.year, list.month} == {2026, 8}
    end

    test "a year the list cannot show lets go, and takes its month along" do
      list = Listing.assemble([on(~D[2026-08-08])], year: 2020, month: 8)

      assert {list.year, list.month} == {nil, nil}
      assert list.shown == 1
    end

    test "a month without its year is no period at all" do
      list = Listing.assemble([on(~D[2026-08-08])], month: 8)

      assert {list.year, list.month} == {nil, nil}
    end
  end
end
