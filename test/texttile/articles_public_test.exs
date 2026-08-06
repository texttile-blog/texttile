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

    test "folds case beyond ASCII, where SQLite's lower() gives up" do
      article = published_post(title: "Über den Bodensee")

      assert Enum.map(Articles.list_published(search: "über"), & &1.id) == [article.id]
      assert Enum.map(Articles.list_published(search: "ÜBER"), & &1.id) == [article.id]
    end

    test "a reader's % and _ are characters, not wildcards" do
      published_post(title: "Fully done", body: "We are 100% done.")
      published_post(title: "Elsewhere", body: "Nothing numeric.")

      assert Articles.list_published(search: "_") == []
      assert [%{title: "Fully done"}] = Articles.list_published(search: "100%")
    end

    test "every word of the term must appear somewhere" do
      both = published_post(title: "Harbor mornings", body: "Fog over the pier.")
      published_post(title: "Harbor evenings", body: "Clear sky.")

      assert Enum.map(Articles.list_published(search: "harbor fog"), & &1.id) == [both.id]
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

  describe "public_path/1" do
    test "a post lives under its publish date" do
      post = published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-08-23])

      assert Articles.public_path(post) == "/2026/08/23/harbor"
    end

    test "the month and the day always carry two digits" do
      post = published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-01-05])

      assert Articles.public_path(post) == "/2026/01/05/harbor"
    end

    test "a page keeps the short address" do
      page = published_page(title: "About", slug: "about-us")

      assert Articles.public_path(page) == "/about-us"
    end

    test "a text without an address yet answers nil" do
      draft = draft_post(title: "Draft")

      assert Articles.public_path(draft) == nil
      assert Articles.public_path(%{draft | slug: "draft"}) == nil
    end
  end

  describe "get_published_post/2" do
    test "finds a published post at its date and slug" do
      post = published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-08-23])

      assert Articles.get_published_post(~D[2026-08-23], "harbor").id == post.id
    end

    test "another day is another address, and no text" do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-08-23])

      assert Articles.get_published_post(~D[2026-08-22], "harbor") == nil
    end

    test "answers nil for pages, drafts, scheduled texts and unknown addresses" do
      page = published_page(title: "About", slug: "about-us", publish_date: ~D[2026-08-23])
      draft_post(title: "Draft", slug: "draft-text")
      scheduled = scheduled_post(title: "Scheduled")

      assert Articles.get_published_post(page.publish_date, "about-us") == nil
      assert Articles.get_published_post(~D[2026-08-23], "draft-text") == nil
      assert Articles.get_published_post(scheduled.publish_date, scheduled.slug) == nil
      assert Articles.get_published_post(~D[2026-08-23], "nowhere") == nil
    end
  end

  describe "get_published_page/1" do
    test "finds a published page by its address" do
      page = published_page(title: "About", slug: "about-us")

      assert Articles.get_published_page("about-us").id == page.id
    end

    test "answers nil for posts, drafts and unknown addresses" do
      published_post(title: "Harbor", slug: "harbor")
      draft_post(title: "Draft", slug: "draft-page", type: "page")

      assert Articles.get_published_page("harbor") == nil
      assert Articles.get_published_page("draft-page") == nil
      assert Articles.get_published_page("nowhere") == nil
    end
  end

  describe "reserved addresses" do
    test "a slug the site itself uses is refused" do
      article = draft_post(title: "Innocent")

      for slug <- ~w(edit login texts tags unlock uploads renditions) do
        assert {:error, changeset} = Articles.update_settings(article, %{slug: slug})
        assert %{slug: [_message]} = errors_on(changeset)
      end
    end

    test "publishing a text whose title is a reserved word walks past it" do
      article = published_post(title: "Texts")
      assert article.slug != "texts"
      assert article.slug =~ ~r/^texts-/
    end
  end

  describe "known_tags/0" do
    test "answers every tag of the desk, the most used one first" do
      published_post(title: "One", tags: "sea, fog")
      draft_post(title: "Two", tags: "Sea, travel")
      published_post(title: "Three", tags: "sea")

      assert Articles.known_tags() == ["sea", "fog", "travel"]
    end

    test "answers an empty list while nobody has tagged anything" do
      published_post(title: "Bare")

      assert Articles.known_tags() == []
    end
  end

  describe "tag_list/1" do
    test "splits, trims, lowercases and deduplicates" do
      assert Articles.tag_list(%{tags: "Sea, fog , sea,,  "}) == ["sea", "fog"]
      assert Articles.tag_list(%{tags: ""}) == []
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
