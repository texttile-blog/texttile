defmodule Texttile.ArticlesArchiveTest do
  @moduledoc """
  The archive over a list: the years it touches, and the months of the
  year that is open.
  """
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Listing

  defp on(date), do: published_post(publish_date: date)

  describe "the years" do
    test "are the years the list touches, newest first, with a count each" do
      articles = [on(~D[2026-08-08]), on(~D[2026-01-02]), on(~D[2024-05-05])]

      assert {[{2026, 2}, {2024, 1}], []} = Listing.periods(articles, nil)
    end

    test "leave out an entry that has no day yet" do
      articles = [on(~D[2026-08-08]), draft_post()]

      assert {[{2026, 1}], []} = Listing.periods(articles, nil)
    end

    test "are empty for a list of entries without a day" do
      assert {[], []} = Listing.periods([draft_post(), draft_post()], nil)
    end
  end

  describe "the months of the open year" do
    test "are only the ones that carry something" do
      articles = [on(~D[2026-08-08]), on(~D[2026-08-20]), on(~D[2026-03-01]), on(~D[2025-11-11])]

      assert {_years, [{3, 1}, {8, 2}]} = Listing.periods(articles, 2026)
    end

    test "stay empty while no year is open" do
      assert {_years, []} = Listing.periods([on(~D[2026-08-08])], nil)
    end

    test "carry a short name" do
      assert Articles.month_name(1) == "Jan"
      assert Articles.month_name(12) == "Dec"
    end
  end

  describe "what a period holds" do
    test "is every entry with no year chosen" do
      assert Listing.in_period?(draft_post(), nil, nil)
    end

    test "is the year, and then the month of it" do
      article = on(~D[2026-08-08])

      assert Listing.in_period?(article, 2026, nil)
      assert Listing.in_period?(article, 2026, 8)
      refute Listing.in_period?(article, 2026, 7)
      refute Listing.in_period?(article, 2025, nil)
    end
  end

  describe "a period that holds nothing" do
    test "lets go of the year" do
      assert {nil, nil} = Listing.settle_period([on(~D[2026-08-08])], 2020, nil)
    end

    test "lets go of the month and keeps the year" do
      assert {2026, nil} = Listing.settle_period([on(~D[2026-08-08])], 2026, 3)
    end

    test "keeps both while they hold something" do
      assert {2026, 8} = Listing.settle_period([on(~D[2026-08-08])], 2026, 8)
    end

    test "drops a month that was asked for without a year" do
      assert {nil, nil} = Listing.settle_period([on(~D[2026-08-08])], nil, 8)
    end
  end
end
