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

      {:ok, _image} = Texttile.Gallery.add_image(article, jpg_fixture(), "pier.jpg")

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "/renditions/640/"
      assert html =~ "The first paragraph carries the lead."
      refute html =~ "The second stays home."
      assert html =~ ~s(href="/tags/sea")
      assert html =~ ~s(href="/tags/fog")
    end

    test "the about block sits at the foot of the front page once filled", %{conn: conn} do
      published_post(title: "A text")

      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ ~s(id="about")

      {:ok, _} = Settings.put(:about_markdown, "We **write** here.")

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="about")
      assert html =~ "<strong>write</strong>"

      # the list behind /texts is not the front door and stays bare
      html = conn |> get(~p"/texts") |> html_response(200)
      refute html =~ ~s(id="about")
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

      html = conn |> get(~p"/harbor-mornings") |> html_response(200)

      assert html =~ "Harbor mornings"
      assert html =~ "<strong>pier</strong>"
      assert html =~ "1 March 2026"
      assert html =~ ~s(href="/tags/sea")
    end

    test "renders a published page too", %{conn: conn} do
      published_page(title: "About", slug: "about-me", body: "I write here.")

      html = conn |> get(~p"/about-me") |> html_response(200)
      assert html =~ "About"
      assert html =~ "I write here."
    end

    test "404s for drafts and unknown addresses", %{conn: conn} do
      draft_post(title: "Draft", slug: "draft-text")

      assert conn |> get(~p"/draft-text") |> html_response(404)
      assert conn |> get(~p"/nowhere") |> html_response(404)
    end

    test "shows the gallery as tiles that link the full picture, with the lightbox shell",
         %{conn: conn} do
      article = published_post(title: "Tiles", slug: "tiles")
      {:ok, image} = Texttile.Gallery.add_image(article, jpg_fixture(), "pier.jpg")

      html = conn |> get(~p"/tiles") |> html_response(200)

      assert html =~ ~s(id="tile-#{image.id}")
      assert html =~ ~s(href="/renditions/max/#{image.path}")
      assert html =~ "/renditions/640/#{image.path}"
      assert html =~ ~s(id="lb")
    end

    test "a text without pictures carries no lightbox", %{conn: conn} do
      published_post(title: "Bare", slug: "bare")

      html = conn |> get(~p"/bare") |> html_response(200)
      refute html =~ ~s(id="lb")
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

    test "protected texts stay out of the archives for locked readers", %{conn: conn} do
      {:ok, _} = Settings.put(:site_password, "sesame")
      published_post(title: "Open", tags: "sea")
      published_post(title: "Hidden", tags: "sea", protected: true)

      html = conn |> get(~p"/tags/sea") |> html_response(200)
      assert html =~ "Open"
      refute html =~ "Hidden"
      assert html =~ "1 text has this tag."
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
  end

  describe "the password gate" do
    setup do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")
      :ok
    end

    test "a locked reader is sent to the gate and back again", %{conn: conn} do
      published_post(title: "Behind the wall", slug: "behind-the-wall")

      conn = get(conn, ~p"/behind-the-wall")
      assert redirected_to(conn) == "/unlock?to=%2Fbehind-the-wall"

      conn = build_conn()
      html = conn |> get(~p"/unlock?to=%2Fbehind-the-wall") |> html_response(200)
      assert html =~ ~s(id="unlock")

      conn =
        build_conn()
        |> post(~p"/unlock", %{"password" => "sesame", "to" => "/behind-the-wall"})

      assert redirected_to(conn) == "/behind-the-wall"

      html = conn |> recycle() |> get(~p"/behind-the-wall") |> html_response(200)
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
    end

    test "an admin session passes without unlocking", %{conn: conn} do
      published_post(title: "Behind the wall", slug: "behind-the-wall")
      user = user_fixture()

      html =
        conn
        |> log_in_user(user)
        |> get(~p"/behind-the-wall")
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

  describe "a protected text on a public site" do
    setup do
      {:ok, _} = Settings.put(:site_password, "sesame")
      :ok
    end

    test "asks for the password on its page and hides everywhere else", %{conn: conn} do
      published_post(title: "Open text")
      published_post(title: "Hidden text", slug: "hidden-text", protected: true, tags: "secret")
      published_page(title: "Hidden page", protected: true)

      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "Open text"
      refute html =~ "Hidden text"
      refute html =~ "Hidden page"

      search = conn |> get(~p"/?q=secret") |> html_response(200)
      refute search =~ "Hidden text"

      conn = get(conn, ~p"/hidden-text")
      assert redirected_to(conn) == "/unlock?to=%2Fhidden-text"
    end

    test "after the password everything appears", %{conn: conn} do
      published_post(title: "Hidden text", slug: "hidden-text", protected: true)

      conn = post(conn, ~p"/unlock", %{"password" => "sesame", "to" => "/hidden-text"})
      assert redirected_to(conn) == "/hidden-text"

      conn = recycle(conn)
      assert conn |> get(~p"/hidden-text") |> html_response(200) =~ "Hidden text"
      assert conn |> get(~p"/") |> html_response(200) =~ "Hidden text"
    end
  end

  describe "renditions" do
    test "are public, for the tiles and the lightbox", %{conn: conn} do
      article = published_post(title: "Tiles")
      {:ok, image} = Texttile.Gallery.add_image(article, jpg_fixture(), "pier.jpg")

      conn = get(conn, "/renditions/320/#{image.path}")
      assert response(conn, 200)
      assert response_content_type(conn, :jpeg) =~ "image/jpeg"
    end
  end
end
