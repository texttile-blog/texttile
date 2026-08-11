defmodule TexttileWeb.SiteHTMLTest do
  use ExUnit.Case, async: true

  alias TexttileWeb.CoreComponents
  alias TexttileWeb.SiteHTML

  describe "lead/1" do
    test "takes the first real paragraph, skipping headings and lone images" do
      body = "# A heading\n\n![alt](/uploads/images/a.jpg)\n\nThe real opening line.\n\nMore."
      assert SiteHTML.lead(%{body: body}) == "The real opening line. More."
    end

    test "reads over the blank lines, so a short first paragraph fills the card" do
      body = "So, the way home.\n\nThe plane left at seven.\n\nWe slept all the way."

      assert SiteHTML.lead(%{body: body}) ==
               "So, the way home. The plane left at seven. We slept all the way."
    end

    test "drops the markers of headings, lists, quotes and rules" do
      body = """
      # Day one

      - the pier
      - the boat

      > It rained.

      ---

      1. Then the train.
      """

      assert SiteHTML.lead(%{body: body}) == "the pier the boat It rained. Then the train."
    end

    test "strips the markdown and keeps the words" do
      body =
        "We **walked** to the [pier](https://example.org) at `dawn`, ![](/uploads/x.jpg) quietly."

      assert SiteHTML.lead(%{body: body}) == "We walked to the pier at dawn, quietly."
    end

    test "cuts at a word before 160 characters and marks the cut" do
      body = String.duplicate("seven letters\n\n", 20)
      lead = SiteHTML.lead(%{body: body})

      assert String.ends_with?(lead, "…")
      assert String.length(lead) <= 161
      refute lead =~ "letter…"
    end

    test "an umlaut lead under the limit keeps its last word" do
      body = String.duplicate("über ", 30) |> String.trim()
      assert String.length(body) == 149
      assert SiteHTML.lead(%{body: body}) == body
    end

    test "an empty body gives an empty lead" do
      assert SiteHTML.lead(%{body: ""}) == ""
      assert SiteHTML.lead(%{body: "# Only a heading"}) == ""
    end
  end

  describe "entry_count/2" do
    test "speaks of all entries, or of the found part" do
      assert CoreComponents.entry_count(1, 1) == "1 entry"
      assert CoreComponents.entry_count(3, 3) == "3 entries"
      assert CoreComponents.entry_count(2, 5) == "2 of 5"
      assert CoreComponents.entry_count(0, 5) == "0 of 5"
    end
  end

  describe "format_date/1" do
    test "writes the date the way the reader pages speak" do
      assert SiteHTML.format_date(~D[2026-07-02]) == "2 July 2026"
      assert SiteHTML.format_date(nil) == ""
    end
  end

  describe "comment_when/1 and comment_heading/1" do
    test "a comment of this year goes without the year, an older one with it" do
      this_year = DateTime.new!(Date.new!(Date.utc_today().year, 7, 2), ~T[10:00:00])
      last_year = DateTime.new!(Date.new!(Date.utc_today().year - 1, 7, 2), ~T[10:00:00])

      assert SiteHTML.comment_when(this_year) == "2 July"
      assert SiteHTML.comment_when(last_year) == "2 July #{Date.utc_today().year - 1}"
    end

    test "the heading counts, and says the word while there is nothing to count" do
      assert SiteHTML.comment_heading(0) == "Comments"
      assert SiteHTML.comment_heading(1) == "1 comment"
      assert SiteHTML.comment_heading(3) == "3 comments"
    end
  end

  describe "body_html/1" do
    test "inline pictures travel as the reading-column rendition" do
      html =
        %{body: "![The pier](/uploads/images/pier.jpg)"}
        |> SiteHTML.body_html()
        |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s(src="/renditions/1320/images/pier.jpg")
      refute html =~ ~s(src="/uploads/)
    end
  end

  describe "gallery_wrap/1, gallery_shape/1 and gallery_size/1" do
    # a tile carries more than this, but the width only counts them
    defp tiles(count), do: for(index <- 1..count//1, do: %{id: index})

    test "three or fewer keep the reading column, one to a picture" do
      for count <- 1..3 do
        assert SiteHTML.gallery_wrap(tiles(count)) == "wrap narrow"
        assert SiteHTML.gallery_shape(tiles(count)) == "gal-#{count}"
      end
    end

    test "four and more leave the column on both sides, in the one grid" do
      for count <- 4..6 do
        assert SiteHTML.gallery_wrap(tiles(count)) == "wrap"
        assert SiteHTML.gallery_shape(tiles(count)) == nil
      end
    end

    test "a picture alone fills the column, so it comes at the reading size" do
      assert SiteHTML.gallery_size(tiles(1)) == :reading
      assert SiteHTML.gallery_size(tiles(2)) == :card
      assert SiteHTML.gallery_size(tiles(9)) == :card
    end
  end
end
