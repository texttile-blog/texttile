defmodule TexttileWeb.SiteHTMLTest do
  use ExUnit.Case, async: true

  alias TexttileWeb.SiteHTML

  describe "lead/1" do
    test "takes the first real paragraph, skipping headings and lone images" do
      body = "# A heading\n\n![alt](/uploads/images/a.jpg)\n\nThe real opening line.\n\nMore."
      assert SiteHTML.lead(%{body: body}) == "The real opening line."
    end

    test "strips the markdown and keeps the words" do
      body =
        "We **walked** to the [pier](https://example.org) at `dawn`, ![](/uploads/x.jpg) quietly."

      assert SiteHTML.lead(%{body: body}) == "We walked to the pier at dawn, quietly."
    end

    test "cuts at a word before 160 characters and marks the cut" do
      body = String.duplicate("seven letters ", 20)
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

  describe "count_label/2" do
    test "speaks of all texts, or of the found part" do
      assert SiteHTML.count_label(1, 1) == "1 text"
      assert SiteHTML.count_label(3, 3) == "3 texts"
      assert SiteHTML.count_label(2, 5) == "2 of 5"
      assert SiteHTML.count_label(0, 5) == "0 of 5"
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
end
