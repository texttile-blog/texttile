defmodule TexttileWeb.E2E.PublicSiteFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Settings

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  describe "reading" do
    test "the front page lists the texts and opens one", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Desert nights", body: "Stars and sand.")

      conn
      |> visit("/")
      |> assert_has("a", text: "Harbor mornings")
      |> click_link("Harbor mornings")
      |> assert_has("h1", text: "Harbor mornings")
      |> assert_has(".prose", text: "Fog over the pier.")
    end

    test "/ jumps into the search and Enter filters the list", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Desert nights", body: "Stars and sand.")

      conn
      |> visit("/")
      |> press("body", "/")
      |> type("input:focus", "harbor")
      |> press("#q", "Enter")
      |> assert_has("a", text: "Harbor mornings")
      |> refute_has("a", text: "Desert nights")
    end
  end

  describe "the password gate" do
    test "asks once, remembers, and returns the reader to the text", %{conn: conn} do
      article = published_post(title: "Behind the wall", slug: "behind-the-wall")
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      conn
      |> visit(Articles.public_path(article))
      |> assert_has("#unlock")
      |> fill_in("Password", with: "sesame")
      |> click_button("Read on")
      |> assert_has("h1", text: "Behind the wall")
      |> visit("/")
      |> assert_has("a", text: "Behind the wall")
    end
  end

  describe "the gallery" do
    test "a tile opens the lightbox, the arrows walk, Escape closes", %{conn: conn} do
      article = published_post(title: "Tiles", slug: "tiles", body: "Pictures below.")
      {:ok, first} = Texttile.Gallery.add_image(article, jpg_fixture(), "pier.jpg")
      {:ok, _second} = Texttile.Gallery.add_image(article, jpg_fixture(), "lagoon.jpg")

      conn
      |> visit(Articles.public_path(article))
      |> click("#tile-#{first.id}")
      |> assert_has("#lbCount", text: "1 / 2")
      |> assert_has("#lbCap", text: "pier.jpg")
      |> press("body", "ArrowRight")
      |> assert_has("#lbCount", text: "2 / 2")
      |> assert_has("#lbCap", text: "lagoon.jpg")
      |> press("body", "Escape")
      |> refute_has("#lbCount", text: "2 / 2")
    end

    test "a picture in the text opens the lightbox too", %{conn: conn} do
      article =
        published_post(
          title: "Inline",
          slug: "inline",
          body: "Look ![the pier](/uploads/images/pier.jpg) here."
        )

      conn
      |> visit(Articles.public_path(article))
      |> click("#body a.bodypic")
      |> assert_has("#lbCount", text: "1 / 1")
      |> assert_has("#lbCap", text: "the pier")
      |> press("body", "Escape")
      |> refute_has("#lbCount", text: "1 / 1")
    end
  end

  describe "walking the blog" do
    test "the pager walks the pages and the text points at the next one", %{conn: conn} do
      {:ok, _} = Settings.put(:posts_per_page, 2)

      for day <- 1..3 do
        published_post(
          title: "Text #{day}",
          slug: "text-#{day}",
          publish_date: Date.new!(2026, 3, day)
        )
      end

      conn
      |> visit("/")
      |> assert_has("a", text: "Text 3")
      |> refute_has("a", text: "Text 1")
      |> click_link("#next-page", "Older texts")
      |> assert_has("a", text: "Text 1")
      |> click_link("#prev-page", "Newer texts")
      |> assert_has("a", text: "Text 3")
      |> click_link("Text 2")
      |> assert_has("h1", text: "Text 2")
      |> assert_has("#prev-post", text: "Text 1")
      |> click_link("#next-post", "Text 3")
      |> assert_has("h1", text: "Text 3")
      |> refute_has("#next-post")
    end
  end

  describe "the foot" do
    # The foot wears .wrap and .f-foot together. `.wrap` writes the
    # padding shorthand, so the space under the last line only holds
    # while the rule that writes it beats `.wrap`. Once it lost, the
    # site name stood on the bottom edge of the page.
    @foot_pad """
    () => parseFloat(getComputedStyle(document.querySelector(".f-foot")).paddingBottom)
    """

    test "keeps space under the last line", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("#foot-signin")
      |> evaluate(@foot_pad, [is_function: true], &assert(&1 >= 24))
    end
  end
end
