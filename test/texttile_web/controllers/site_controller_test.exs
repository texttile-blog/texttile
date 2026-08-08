defmodule TexttileWeb.SiteControllerTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Settings

  setup do
    File.rm_rf!(Texttile.Uploads.root())
    :ok
  end

  describe "the front page" do
    test "lists published posts, newest first, and nothing else", %{conn: conn} do
      old = published_post(title: "Old text", publish_date: ~D[2026-01-05])
      new = published_post(title: "New text", publish_date: ~D[2026-03-01])
      draft_post(title: "Secret draft")
      scheduled_post(title: "Not yet")
      page = published_page(title: "About the blog")

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="text-#{new.id}")
      assert html =~ ~s(id="text-#{old.id}")
      refute html =~ "Secret draft"
      refute html =~ "Not yet"

      # newest first
      {new_at, _} = :binary.match(html, "New text")
      {old_at, _} = :binary.match(html, "Old text")
      assert new_at < old_at

      # the page lives in the menu, not in the list
      assert html =~ ~s(id="menu-page-#{page.id}")
      refute html =~ ~s(id="text-#{page.id}")
    end

    test "carries the search form and filters by q", %{conn: conn} do
      published_post(title: "Harbor mornings", tags: "sea")
      published_post(title: "Desert nights", body: "Sand everywhere.")

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="q")

      html = conn |> get(~p"/?q=harbor") |> html_response(200)
      assert html =~ "Harbor mornings"
      refute html =~ "Desert nights"

      html = conn |> get(~p"/?q=sand") |> html_response(200)
      assert html =~ "Desert nights"
      refute html =~ "Harbor mornings"
    end

    test "shows each post's preview tile, lead line and tag links", %{conn: conn} do
      article =
        published_post(
          title: "With a picture",
          body: "The first paragraph carries the lead.\n\nThe second stays home.",
          tags: "sea, fog"
        )

      {:ok, _image} = Texttile.Gallery.add_file(article, jpg_fixture(), "pier.jpg")

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "/renditions/640/"
      assert html =~ "The first paragraph carries the lead."
      refute html =~ "The second stays home."
      assert html =~ ~s(href="/tags/sea")
      assert html =~ ~s(href="/tags/fog")
      refute html =~ "cimg blank"
    end

    test "a text without a picture keeps the square, so the grid holds", %{conn: conn} do
      published_post(title: "Without a picture")

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "cimg blank"
      refute html =~ "/renditions/640/"
    end

    test "the about block sits at the foot of every reader page once filled", %{conn: conn} do
      published_post(title: "A text", slug: "a-text", publish_date: ~D[2026-03-01])

      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ ~s(id="about")

      {:ok, _} = Settings.put(:about_markdown, "We **write** here.")

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="about")
      assert html =~ "<strong>write</strong>"

      assert conn |> get(~p"/texts") |> html_response(200) =~ ~s(id="about")
      assert conn |> get(~p"/2026/03/01/a-text") |> html_response(200) =~ ~s(id="about")
    end
  end

  describe "the article page" do
    test "renders title, date and the markdown body", %{conn: conn} do
      published_post(
        title: "Harbor mornings",
        body: "Fog over the **pier**.",
        slug: "harbor-mornings",
        publish_date: ~D[2026-03-01],
        tags: "sea, fog"
      )

      html = conn |> get(~p"/2026/03/01/harbor-mornings") |> html_response(200)

      assert html =~ "Harbor mornings"
      assert html =~ "<strong>pier</strong>"
      assert html =~ "1 March 2026"
      assert html =~ ~s(href="/tags/sea")
    end

    test "a post has no address without its date", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])

      assert conn |> get(~p"/harbor") |> html_response(404)
    end

    test "another day than the publish date is a 404", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])

      assert conn |> get(~p"/2026/03/02/harbor") |> html_response(404)
      assert conn |> get(~p"/2025/03/01/harbor") |> html_response(404)
    end

    test "a date the calendar does not know is a 404", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])

      assert conn |> get("/2026/3/1/harbor") |> html_response(404)
      assert conn |> get("/2026/02/31/harbor") |> html_response(404)
      assert conn |> get("/march/03/01/harbor") |> html_response(404)
    end

    test "renders a published page at its short address", %{conn: conn} do
      published_page(title: "About", slug: "about-me", body: "I write here.")

      html = conn |> get(~p"/about-me") |> html_response(200)
      assert html =~ "About"
      assert html =~ "I write here."
    end

    test "a page keeps its short address and wears no date", %{conn: conn} do
      page = published_page(title: "About", slug: "about-me", publish_date: ~D[2026-03-01])

      assert Texttile.Articles.public_path(page) == "/about-me"
      assert conn |> get(~p"/2026/03/01/about-me") |> html_response(404)
    end

    test "404s for drafts and unknown addresses", %{conn: conn} do
      draft = draft_post(title: "Draft", slug: "draft-text")

      assert conn |> get(~p"/draft-text") |> html_response(404)
      assert conn |> get(~p"/2026/03/01/draft-text") |> html_response(404)
      assert conn |> get(~p"/nowhere") |> html_response(404)
      assert draft.slug == "draft-text"
    end

    test "shows the gallery as tiles that link the original, with the lightbox shell",
         %{conn: conn} do
      article = published_post(title: "Tiles", slug: "tiles", publish_date: ~D[2026-03-01])
      {:ok, image} = Texttile.Gallery.add_file(article, jpg_fixture(), "pier.jpg")

      html = conn |> get(~p"/2026/03/01/tiles") |> html_response(200)

      assert html =~ ~s(id="tile-#{image.id}")
      # the crawler follows the link to the file as it came
      assert html =~ ~s(href="/uploads/#{image.path}")
      # the reader gets the scaled one, in the lightbox
      assert html =~ ~s(data-full="/renditions/max/#{image.path}")
      assert html =~ "/renditions/640/#{image.path}"
      assert html =~ ~s(id="lb")
    end

    test "a picture in the text links its original and opens in the lightbox", %{conn: conn} do
      published_post(
        title: "Inline",
        slug: "inline",
        publish_date: ~D[2026-03-01],
        body: "Look ![pier](/uploads/images/pier.jpg) here."
      )

      html = conn |> get(~p"/2026/03/01/inline") |> html_response(200)

      assert html =~ ~s(href="/uploads/images/pier.jpg")
      assert html =~ ~s(data-full="/renditions/max/images/pier.jpg")
      assert html =~ ~s(src="/renditions/1320/images/pier.jpg")
      assert html =~ ~s(id="lb")
    end

    test "a text without pictures carries no lightbox", %{conn: conn} do
      published_post(title: "Bare", slug: "bare", publish_date: ~D[2026-03-01])

      html = conn |> get(~p"/2026/03/01/bare") |> html_response(200)
      refute html =~ ~s(id="lb")
    end

    test "keeps the line breaks a reader typed into a comment", %{conn: conn} do
      article = published_post(title: "Talk", slug: "talk", publish_date: ~D[2026-03-01])
      {:ok, _} = Settings.put(:comments_require_confirmation, false)

      {:ok, comment} =
        Texttile.Comments.post(
          article,
          %{"name" => "Ada", "email" => "ada@example.org", "body" => "First line\nsecond line"},
          confirm_url: &"http://localhost/comments/confirm/#{&1}"
        )

      html = conn |> get(~p"/2026/03/01/talk") |> html_response(200)

      assert html =~ ~s(id="comment-#{comment.id}")
      assert html =~ "First line\nsecond line"
      assert html =~ "comment-body"
    end

    test "the About block from Settings stands under the text", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])
      {:ok, _} = Settings.put(:about_markdown, "We are **kb** and julia.")

      html = conn |> get(~p"/2026/03/01/harbor") |> html_response(200)

      assert html =~ ~s(id="about")
      assert html =~ "<strong>kb</strong>"
    end

    test "no About text, no About block", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])

      html = conn |> get(~p"/2026/03/01/harbor") |> html_response(200)
      refute html =~ ~s(id="about")
    end

    # Everything above the band belongs to the text, everything on it
    # belongs to the blog. About and Subscribe stand there side by
    # side, out of the reading column and on a ground of their own.
    test "About and Subscribe stand on the band under the text", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])
      {:ok, _} = Settings.put(:about_markdown, "We are kb and julia.")

      html = conn |> get(~p"/2026/03/01/harbor") |> html_response(200)

      assert html =~ ~s(id="foot-band")
      assert html =~ ~s(id="about")
      assert html =~ ~s(id="subscribe")

      {band_at, _} = :binary.match(html, ~s(id="foot-band"))
      {about_at, _} = :binary.match(html, ~s(id="about"))
      {comments_at, _} = :binary.match(html, ~s(id="comments"))
      assert comments_at < band_at
      assert band_at < about_at
    end

    test "a reader never sees the way to the desk", %{conn: conn} do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])

      html = conn |> get(~p"/2026/03/01/harbor") |> html_response(200)
      refute html =~ ~s(id="edit-text")
    end

    test "a signed-in admin gets an Edit link beside the date", %{conn: conn} do
      article = published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-03-01])
      conn = log_in_user(conn, user_fixture())

      html = conn |> get(~p"/2026/03/01/harbor") |> html_response(200)

      assert html =~ ~s(id="edit-text")
      assert html =~ ~s(href="/admin/texts/#{article.id}")
    end

    test "the Edit link stands on a page too, which carries no date", %{conn: conn} do
      page = published_page(title: "About", slug: "about-me")
      conn = log_in_user(conn, user_fixture())

      html = conn |> get(~p"/about-me") |> html_response(200)

      assert html =~ ~s(id="edit-text")
      assert html =~ ~s(href="/admin/texts/#{page.id}")
    end
  end

  describe "the way from one post to the next" do
    setup do
      %{
        old: published_post(title: "The oldest", slug: "oldest", publish_date: ~D[2026-01-05]),
        middle: published_post(title: "The middle", slug: "middle", publish_date: ~D[2026-02-05]),
        new: published_post(title: "The newest", slug: "newest", publish_date: ~D[2026-03-05])
      }
    end

    test "a post in the middle points both ways", %{conn: conn, old: old, new: new} do
      html = conn |> get(~p"/2026/02/05/middle") |> html_response(200)

      assert html =~ ~s(id="prev-post")
      assert html =~ Texttile.Articles.public_path(old)
      assert html =~ ~s(id="next-post")
      assert html =~ Texttile.Articles.public_path(new)
      # the strip that ends a text: the width of the gallery, not of
      # the reading column
      assert html =~ ~s(class="textnav")
    end

    test "the newest post has nothing newer, the oldest nothing older", %{conn: conn} do
      newest = conn |> get(~p"/2026/03/05/newest") |> html_response(200)
      assert newest =~ ~s(id="prev-post")
      refute newest =~ ~s(id="next-post")

      oldest = conn |> get(~p"/2026/01/05/oldest") |> html_response(200)
      refute oldest =~ ~s(id="prev-post")
      assert oldest =~ ~s(id="next-post")
    end

    test "a page stands on its own", %{conn: conn} do
      published_page(title: "About", slug: "about-me")

      html = conn |> get(~p"/about-me") |> html_response(200)
      refute html =~ ~s(id="prev-post")
      refute html =~ ~s(id="next-post")
    end
  end

  describe "pagination" do
    test "shows the page size from Settings and walks the pages", %{conn: conn} do
      for day <- 1..7 do
        published_post(title: "Text #{day}", publish_date: Date.new!(2026, 3, day))
      end

      {:ok, _} = Settings.put(:posts_per_page, 3)

      first = conn |> get(~p"/") |> html_response(200)
      assert first =~ "Text 7"
      assert first =~ "Text 5"
      refute first =~ "Text 4"
      refute first =~ ~s(id="prev-page")
      assert first =~ ~s(id="next-page")

      second = conn |> get(~p"/?page=2") |> html_response(200)
      assert second =~ "Text 4"
      refute second =~ "Text 7"
      assert second =~ ~s(id="prev-page")
      assert second =~ ~s(id="next-page")

      last = conn |> get(~p"/?page=3") |> html_response(200)
      assert last =~ "Text 1"
      refute last =~ ~s(id="next-page")
    end

    test "ten texts a page by default, and no pager while one page holds all", %{conn: conn} do
      published_post(title: "The only one")

      html = conn |> get(~p"/") |> html_response(200)
      assert Settings.get(:posts_per_page) == 10
      refute html =~ ~s(id="pager")
    end

    test "a page number nobody has answers with the last one", %{conn: conn} do
      published_post(title: "Alone")

      html = conn |> get(~p"/?page=99") |> html_response(200)
      assert html =~ "Alone"
    end

    test "the search keeps its term across the pages", %{conn: conn} do
      for day <- 1..4 do
        published_post(title: "Harbor #{day}", publish_date: Date.new!(2026, 3, day))
      end

      {:ok, _} = Settings.put(:posts_per_page, 2)

      html = conn |> get(~p"/?q=harbor") |> html_response(200)
      assert html =~ "q=harbor"
      assert html =~ ~s(id="next-page")
    end
  end

  describe "tag archives" do
    test "a tag page lists its texts and the other tags with counts", %{conn: conn} do
      sea = published_post(title: "Harbor mornings", tags: "Sea, fog")
      published_post(title: "Desert nights", tags: "travel")

      html = conn |> get(~p"/tags/sea") |> html_response(200)

      assert html =~ "#sea"
      assert html =~ "text has this tag."
      assert html =~ ~s(id="text-#{sea.id}")
      refute html =~ "Desert nights"

      # the other tags stay on the page, each a way into its archive
      assert html =~ ~s(href="/tags/fog")
      assert html =~ ~s(href="/tags/travel")
    end

    test "a tag nobody uses is a 404", %{conn: conn} do
      published_post(title: "A text", tags: "sea")
      assert conn |> get(~p"/tags/nowhere") |> html_response(404)
    end
  end

  describe "the menu" do
    test "published pages appear automatically, sorted by publish date", %{conn: conn} do
      late = published_page(title: "Imprint", publish_date: ~D[2026-04-01])
      early = published_page(title: "About", publish_date: ~D[2026-01-01])
      draft_post(title: "Draft page", type: "page")
      published_post(title: "A post title")

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="menu-page-#{early.id}")
      assert html =~ ~s(id="menu-page-#{late.id}")
      refute html =~ "Draft page"

      {early_at, _} = :binary.match(html, ~s(id="menu-page-#{early.id}"))
      {late_at, _} = :binary.match(html, ~s(id="menu-page-#{late.id}"))
      assert early_at < late_at

      # posts never enter the menu
      refute html =~ ~s(id="menu-page-) <> "A post title"
    end

    test "a fixed front page becomes Home and moves the list to /texts", %{conn: conn} do
      page = published_page(title: "Welcome", slug: "welcome", body: "The front door.")
      published_post(title: "A post")
      {:ok, _} = Settings.put(:front_page, "page:#{page.id}")

      front = conn |> get(~p"/") |> html_response(200)
      assert front =~ "The front door."
      assert front =~ ~s(id="menu-home")
      assert front =~ ~s(id="menu-texts" href="/texts")

      # the front page never doubles as a menu page
      refute front =~ ~s(id="menu-page-#{page.id}")

      texts = conn |> get(~p"/texts") |> html_response(200)
      assert texts =~ "A post"
    end

    test "without a fixed front page, Blog is the first door and Home is gone", %{conn: conn} do
      published_post(title: "A post")

      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ ~s(id="menu-home")
      assert html =~ ~s(id="menu-texts" href="/")
    end

    test "a fixed front page that disappears falls back to the list", %{conn: conn} do
      user = Texttile.AccountsFixtures.user_fixture()
      page = published_page(title: "Welcome", user: user)
      published_post(title: "A post")
      {:ok, _} = Settings.put(:front_page, "page:#{page.id}")

      {:ok, _} = Texttile.Articles.unpublish(page, user)

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "A post"
      refute html =~ ~s(id="menu-home")
    end
  end

  describe "the password gate" do
    setup do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")
      :ok
    end

    test "a locked reader is sent to the gate and back again", %{conn: conn} do
      published_post(
        title: "Behind the wall",
        slug: "behind-the-wall",
        publish_date: ~D[2026-03-01]
      )

      conn = get(conn, ~p"/2026/03/01/behind-the-wall")
      assert redirected_to(conn) == "/unlock?to=%2F2026%2F03%2F01%2Fbehind-the-wall"

      conn = build_conn()
      html = conn |> get(~p"/unlock?to=%2F2026%2F03%2F01%2Fbehind-the-wall") |> html_response(200)
      assert html =~ ~s(id="unlock")

      conn =
        build_conn()
        |> post(~p"/unlock", %{
          "password" => "sesame",
          "to" => "/2026/03/01/behind-the-wall"
        })

      assert redirected_to(conn) == "/2026/03/01/behind-the-wall"

      html = conn |> recycle() |> get(~p"/2026/03/01/behind-the-wall") |> html_response(200)
      assert html =~ "Behind the wall"
    end

    test "the front page redirects with its own return path", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == "/unlock?to=%2F"
    end

    test "a wrong password stays at the gate and says so", %{conn: conn} do
      conn = post(conn, ~p"/unlock", %{"password" => "wrong", "to" => "/"})
      html = html_response(conn, 200)
      assert html =~ ~s(id="unlock-error")
      refute get_session(conn, :site_unlocked)
    end

    test "the gate never forwards to another site", %{conn: conn} do
      conn = post(conn, ~p"/unlock", %{"password" => "sesame", "to" => "https://evil.example"})
      assert redirected_to(conn) == "/"

      conn = post(build_conn(), ~p"/unlock", %{"password" => "sesame", "to" => "//evil.example"})
      assert redirected_to(conn) == "/"

      # a backslash path would make the redirect itself raise
      conn = post(build_conn(), ~p"/unlock", %{"password" => "sesame", "to" => "/\\evil.example"})
      assert redirected_to(conn) == "/"
    end

    test "an unlocked reader who lands on the gate is sent along", %{conn: conn} do
      published_page(title: "Behind the wall", slug: "behind-the-wall")

      conn = post(conn, ~p"/unlock", %{"password" => "sesame", "to" => "/"})

      conn = conn |> recycle() |> get(~p"/unlock?to=%2Fbehind-the-wall")
      assert redirected_to(conn) == "/behind-the-wall"
    end

    test "an admin session passes without unlocking", %{conn: conn} do
      published_post(
        title: "Behind the wall",
        slug: "behind-the-wall",
        publish_date: ~D[2026-03-01]
      )

      user = user_fixture()

      html =
        conn
        |> log_in_user(user)
        |> get(~p"/2026/03/01/behind-the-wall")
        |> html_response(200)

      assert html =~ "Behind the wall"
    end

    test "a blank stored password leaves the site open", %{conn: conn} do
      {:ok, _} = Settings.put(:site_password, "")
      published_post(title: "Open after all")

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "Open after all"
    end
  end

  describe "renditions" do
    test "are public, for the tiles and the lightbox", %{conn: conn} do
      article = published_post(title: "Tiles")
      {:ok, image} = Texttile.Gallery.add_file(article, jpg_fixture(), "pier.jpg")

      conn = get(conn, "/renditions/320/#{image.path}")
      assert response(conn, 200)
      assert response_content_type(conn, :jpeg) =~ "image/jpeg"
    end
  end
end
