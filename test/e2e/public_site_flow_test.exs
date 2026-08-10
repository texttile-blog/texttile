defmodule TexttileWeb.E2E.PublicSiteFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles
  alias Texttile.Settings

  describe "reading" do
    test "the front page lists the texts and opens one", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Desert nights", body: "Stars and sand.")

      conn
      |> open_page("/")
      |> assert_has("a", text: "Harbor mornings")
      |> click_link("Harbor mornings")
      |> assert_has("h1", text: "Harbor mornings")
      |> assert_has(".prose", text: "Fog over the pier.")
    end

    test "/ jumps into the search and Enter filters the list", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Desert nights", body: "Stars and sand.")

      conn
      |> open_page("/")
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
      |> open_page(Articles.public_path(article))
      |> assert_has("#unlock")
      |> fill_in("Password", with: "sesame")
      |> click_button("Read on")
      |> assert_has("h1", text: "Behind the wall")
      |> open_page("/")
      |> assert_has("a", text: "Behind the wall")
    end

    # The card was centred on the page while everything on it ran down
    # the left edge, so the mark, the title and the button each began
    # somewhere else. The gate is four short things, not a form to work
    # through, so they stand on one axis.
    # Two things, and the first one is the one that was wrong: the card
    # itself against the middle of the page. `body.site > main` is a
    # flex column, which turned the card's `justify-center` into
    # vertical centring and left it against the left edge.
    #
    # Then what is drawn on the card, because a full-width box is
    # centred whatever it holds: the mark and the title from the left
    # edge of the one to the right edge of the other, and the rendered
    # range of each line of words.
    @gate_axis """
    () => {
      const card = document.querySelector("#unlock").parentElement
      const box = card.getBoundingClientRect()
      // the space the card has, measured on the element that gives it:
      // the viewport is the wrong ruler, because the site layout
      // scrolls the body and a scrollbar takes part of the width
      const main = document.querySelector("main")
      const mb = main.getBoundingClientRect(), ms = getComputedStyle(main)
      const room = [mb.left + parseFloat(ms.paddingLeft),
                    mb.right - parseFloat(ms.paddingRight)]
      const page = Math.abs((box.left - room[0]) - (room[1] - box.right))
      const axis = box.left + box.width / 2
      const off = r => Math.abs(r.left + r.width / 2 - axis)
      const kids = [...card.firstElementChild.children].map(k => k.getBoundingClientRect())
      const head = {left: kids[0].left, width: kids[kids.length - 1].right - kids[0].left}
      const words = el => {
        const range = document.createRange()
        range.selectNodeContents(el)
        return range.getBoundingClientRect()
      }
      return Math.max(page,
                      off(head),
                      off(words(card.querySelector("p"))),
                      off(words(document.querySelector("#unlock button"))))
    }
    """

    test "stands on one axis and says only what it must", %{conn: conn} do
      published_post(title: "Behind the wall", slug: "behind-the-wall")
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      conn
      |> open_page("/")
      |> assert_has("#unlock")
      |> refute_has("body", text: "One password opens the whole blog")
      |> evaluate(@gate_axis, [is_function: true], &assert(&1 < 1.5))
    end
  end

  describe "the gallery" do
    test "a tile opens the lightbox, the arrows walk, Escape closes", %{conn: conn} do
      article = published_post(title: "Tiles", slug: "tiles", body: "Pictures below.")
      {:ok, first} = Texttile.Gallery.add_file(article, jpg_fixture(), "pier.jpg")
      {:ok, _second} = Texttile.Gallery.add_file(article, jpg_fixture(), "lagoon.jpg")

      conn
      |> open_page(Articles.public_path(article))
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
      |> open_page(Articles.public_path(article))
      |> click("#body a.bodypic")
      |> assert_has("#lbCount", text: "1 / 1")
      |> assert_has("#lbCap", text: "the pier")
      |> press("body", "Escape")
      |> refute_has("#lbCount", text: "1 / 1")
    end
  end

  describe "the feed" do
    test "the foot points at it, and the feed carries the texts", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")

      conn
      |> open_page("/")
      |> assert_has("#foot-feed", text: "RSS")
      |> click_link("#foot-feed", "RSS")
      |> assert_has("body", text: "Harbor mornings")
    end

    test "is gone once a password guards the blog", %{conn: conn} do
      published_post(title: "Behind the wall")
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      conn
      |> open_page("/")
      |> fill_in("Password", with: "sesame")
      |> click_button("Read on")
      |> assert_has("a", text: "Behind the wall")
      |> refute_has("#foot-feed")
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
      |> open_page("/")
      |> assert_has("a", text: "Text 3")
      |> refute_has("a", text: "Text 1")
      |> click_link("#next-page", "Older")
      |> assert_has("a", text: "Text 1")
      |> click_link("#prev-page", "Newer")
      |> assert_has("a", text: "Text 3")
      |> click_link("Text 2")
      |> assert_has("h1", text: "Text 2")
      |> assert_has("#prev-post", text: "Text 1")
      |> click_link("#next-post", "Text 3")
      |> assert_has("h1", text: "Text 3")
      |> refute_has("#next-post")
    end
  end

  describe "what a reader writes on" do
    # The subscribe row is a field and a button side by side. A button
    # of a fixed height beside a field that takes its height from its
    # padding is two boxes that nearly line up, which reads as sloppy
    # work. They are one row, so they are one height.
    @subscribe_row """
    () => {
      const box = el => document.querySelector(el).getBoundingClientRect()
      const field = box("#newsletter-form input[type=email]")
      const button = box("#newsletter-form button")
      return Math.max(Math.abs(field.height - button.height),
                      Math.abs(field.top - button.top),
                      Math.abs(field.bottom - button.bottom))
    }
    """

    # The comment box asked for words in a box barely taller than the
    # one-line fields over it. Between "a line" and "a text" it was
    # neither, so it is a text: room for several lines before a word is
    # typed, and it still grows with what is written.
    @comment_box """
    () => {
      const box = el => document.querySelector(el).getBoundingClientRect()
      return box("#comment-form textarea").height / box("#comment-name").height
    }
    """

    test "the subscribe row lines up and the comment box asks for words", %{conn: conn} do
      article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

      conn
      |> open_page(Articles.public_path(article))
      |> assert_has("#comments", text: "Post a comment")
      |> evaluate(@subscribe_row, [is_function: true], &assert(&1 <= 1))
      |> evaluate(@comment_box, [is_function: true], &assert(&1 >= 2.5))
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
      |> open_page("/")
      |> assert_has("#foot-signin")
      |> evaluate(@foot_pad, [is_function: true], &assert(&1 >= 24))
    end

    # The sheet belongs to the browser. This one has none, so the word
    # is not offered: a button that answers nothing is worse than no
    # button. The next test puts a sheet in and gets the word.
    @share_hidden """
    () => document.getElementById("foot-share").hidden
    """

    test "offers no Share where the browser has no sheet", %{conn: conn} do
      conn
      |> open_page("/")
      |> evaluate(@share_hidden, [is_function: true], &assert(&1 == true))
    end

    # A browser with a sheet, put in before the page's own script runs,
    # the way the browsers that have one do it.
    @a_sheet """
    navigator.share = (data) => { window.__shared = data; return Promise.resolve() }
    """

    @what_was_shared """
    () => [window.__shared && window.__shared.url, window.__shared && window.__shared.title]
    """

    test "hands the page to the sheet the browser opens", %{conn: conn} do
      published_post(title: "Harbor mornings", slug: "harbor", publish_date: ~D[2026-03-01])

      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(conn.context_id,
          source: @a_sheet,
          timeout: 5_000
        )

      conn
      |> open_page("/2026/03/01/harbor")
      |> click_button("#foot-share", "Share")
      |> evaluate(@what_was_shared, [is_function: true], fn [url, title] ->
        assert url =~ "/2026/03/01/harbor"
        assert title =~ "Harbor mornings"
      end)
    end
  end
end
