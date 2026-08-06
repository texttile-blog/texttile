defmodule Texttile.ArticlesPublicTest do
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  describe "list_published/1" do
    test "answers published posts only, newest publish date first" do
      old = published_post(title: "Old", publish_date: ~D[2026-01-05])
      new = published_post(title: "New", publish_date: ~D[2026-03-01])
      mid = published_post(title: "Mid", publish_date: ~D[2026-02-11])
      draft_post(title: "Draft")
      scheduled_post(title: "Scheduled")
      published_page(title: "A page")

      assert Enum.map(Articles.list_published(), & &1.id) == [new.id, mid.id, old.id]
    end

    test "searches title, tags and full text, case-insensitively" do
      by_title = published_post(title: "Harbor mornings")
      by_tags = published_post(title: "Elsewhere", tags: "harbor, fog")
      by_body = published_post(title: "Inland", body: "We drove down to the HARBOR.")
      published_post(title: "Desert", body: "Nothing here.")

      found = Articles.list_published(search: "harbor")

      assert Enum.sort(Enum.map(found, & &1.id)) ==
               Enum.sort([by_title.id, by_tags.id, by_body.id])
    end

    test "leaves protected texts out unless asked to include them" do
      open = published_post(title: "Open")
      hidden = published_post(title: "Hidden", protected: true)

      assert Enum.map(Articles.list_published(include_protected: false), & &1.id) == [open.id]

      ids = Articles.list_published(include_protected: true) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([open.id, hidden.id])
    end
  end

  describe "list_pages/1" do
    test "answers published pages, oldest publish date first" do
      late = published_page(title: "Imprint", publish_date: ~D[2026-04-01])
      early = published_page(title: "About", publish_date: ~D[2026-01-01])
      draft_post(title: "Draft page", type: "page")
      published_post(title: "A post")

      assert Enum.map(Articles.list_pages(), & &1.id) == [early.id, late.id]
    end

    test "leaves protected pages out when asked" do
      open = published_page(title: "Open page")
      published_page(title: "Hidden page", protected: true)

      assert Enum.map(Articles.list_pages(include_protected: false), & &1.id) == [open.id]
    end
  end

  describe "get_published_by_slug/1" do
    test "finds published posts and pages by their address" do
      post = published_post(title: "Harbor", slug: "harbor")
      page = published_page(title: "About", slug: "about-us")

      assert Articles.get_published_by_slug("harbor").id == post.id
      assert Articles.get_published_by_slug("about-us").id == page.id
    end

    test "answers nil for drafts, scheduled texts and unknown addresses" do
      draft_post(title: "Draft", slug: "draft-text")
      scheduled = scheduled_post(title: "Scheduled")

      assert Articles.get_published_by_slug("draft-text") == nil
      assert Articles.get_published_by_slug(scheduled.slug) == nil
      assert Articles.get_published_by_slug("nowhere") == nil
    end
  end

  describe "reserved addresses" do
    test "a slug the site itself uses is refused" do
      article = draft_post(title: "Innocent")

      for slug <- ~w(desk login texts about unlock uploads renditions) do
        assert {:error, changeset} = Articles.update_settings(article, %{slug: slug})
        assert %{slug: [_message]} = errors_on(changeset)
      end
    end

    test "publishing a text whose title is a reserved word walks past it" do
      article = published_post(title: "About")
      assert article.slug != "about"
      assert article.slug =~ ~r/^about-/
    end
  end

  describe "the protected switch" do
    test "update_settings flips it" do
      article = draft_post(title: "Secret")
      refute article.protected

      assert {:ok, article} = Articles.update_settings(article, %{protected: true})
      assert article.protected
    end
  end
end
