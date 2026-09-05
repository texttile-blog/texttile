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

    # An empty field used to leave the list exactly as the deleted word
    # had left it. Nothing submits a form here: the browser's clear
    # cross does not, Escape does not, and a held backspace does not.
    test "emptying the field shows the whole list again", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Desert nights", body: "Stars and sand.")

      conn
      |> open_page("/blog?q=harbor")
      |> refute_has("a", text: "Desert nights")
      |> fill_in("Search the entries", with: "")
      |> assert_has("a", text: "Desert nights", timeout: 5_000)
      |> assert_has("a", text: "Harbor mornings")
    end

    # The year narrows what the field found, so with no term there is
    # nothing left for it to narrow.
    test "Escape in the field drops the term and the year with it", %{conn: conn} do
      published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Desert nights", body: "Stars and sand.")

      conn
      |> open_page("/blog?q=harbor&y=2023")
      |> refute_has("a", text: "Desert nights")
      |> click("#q")
      |> press("#q", "Escape")
      |> assert_has("a", text: "Desert nights", timeout: 5_000)
      |> assert_has("#q[value='']")
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
      |> click_button("To the blog")
      |> assert_has("h1", text: "Behind the wall")
      |> open_page("/")
      |> assert_has("a", text: "Behind the wall")
    end

    # Two things. The card stands in the middle of the page: the same
    # room to its left and to its right, measured on `main`, because
    # `body.site > main` is a flex column that once turned the card's
    # `justify-center` into vertical centring and left it against the
    # left edge.
    #
    # Everything on the card runs down its left edge: the mark with the
    # title beside it, the rendered range of the line that says why,
    # and the field. Words are measured with a range, because a
    # full-width box tells nothing about where its text begins.
    @gate_edge """
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
      const edge = r => Math.abs(r.left - box.left)
      const words = el => {
        const range = document.createRange()
        range.selectNodeContents(el)
        return range.getBoundingClientRect()
      }
      return Math.max(page,
                      edge(card.firstElementChild.getBoundingClientRect()),
                      edge(words(card.querySelector("p"))),
                      edge(document.querySelector("#password").getBoundingClientRect()))
    }
    """

    test "runs down one left edge and says only what it must", %{conn: conn} do
      published_post(title: "Behind the wall", slug: "behind-the-wall")
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      conn
      |> open_page("/")
      |> assert_has("#unlock")
      |> refute_has("body", text: "One password opens the whole blog")
      |> evaluate(@gate_edge, [is_function: true], &assert(&1 < 1.5))
    end
  end

  describe "the gallery" do
    test "a tile opens the lightbox, the arrows walk, Escape closes", %{conn: conn} do
      article = published_post(title: "Tiles", slug: "tiles", body: "Pictures below.")
      {:ok, first} = Texttile.Gallery.add_file(article, jpg_fixture(), "pier.jpg")
      {:ok, second} = Texttile.Gallery.add_file(article, jpg_fixture(), "lagoon.jpg")
      {:ok, _} = Texttile.Gallery.set_description(article.id, first.id, "The pier at sunrise.")

      {:ok, _} =
        Texttile.Gallery.set_description(article.id, second.id, "Still water in the lagoon.")

      conn
      |> open_page(Articles.public_path(article))
      |> click("#tile-#{first.id}")
      |> assert_has("#lbCount", text: "1 / 2")
      |> assert_has("#lbCap", text: "The pier at sunrise.")
      |> press("body", "ArrowRight")
      |> assert_has("#lbCount", text: "2 / 2")
      |> assert_has("#lbCap", text: "Still water in the lagoon.")
      |> press("body", "Escape")
      |> refute_has("#lbCount", text: "2 / 2")
    end

    test "Tab stays inside the open lightbox", %{conn: conn} do
      article = published_post(title: "Trap", slug: "trap", body: "Pictures below.")
      {:ok, first} = Texttile.Gallery.add_file(article, jpg_fixture(), "pier.jpg")

      # the page behind the overlay is not there: however often Tab is
      # pressed, focus never leaves the lightbox
      session =
        conn
        |> open_page(Articles.public_path(article))
        |> click("#tile-#{first.id}")
        |> assert_has("#lbCount", text: "1 / 1")

      for _step <- 1..6, do: press(session, "body", "Tab")

      evaluate(
        session,
        "() => document.getElementById('lb').contains(document.activeElement)",
        [is_function: true],
        &assert(&1 == true)
      )
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

  describe "the reader bar" do
    # The bar is the mark, the name of the blog, the line beside it and
    # the menu. The name is the only one of them that may give way: a
    # long one pushed the menu out of the bar on a narrow phone.
    @bar_fits """
    () => {
      const head = document.querySelector(".site-head")
      const nav = document.querySelector(".site-nav").getBoundingClientRect()
      return Math.max(head.scrollWidth - head.clientWidth,
                      nav.right - head.getBoundingClientRect().right)
    }
    """

    @tag browser_context_opts: [viewport: %{width: 320, height: 700}]
    test "keeps the menu in it when the site title is long", %{conn: conn} do
      {:ok, _} = Settings.put(:site_title, "The blog of Klaus and Julia Breyer")

      conn
      |> open_page("/")
      |> assert_has(".site-name", text: "The blog of Klaus and Julia Breyer")
      |> evaluate(@bar_fits, [is_function: true], &assert(&1 <= 1))
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
