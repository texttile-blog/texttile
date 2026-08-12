defmodule Texttile.ArticlesReadingTest do
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Reading

  defp ran_ahead(attrs \\ %{}) do
    article = published_post(Map.new(attrs))
    {:ok, article} = Articles.update_text(article, %{title: "Rewritten", body: "New words."})
    article
  end

  describe "audience/1" do
    test "nobody signed in is a reader, anybody signed in is an admin" do
      assert Reading.audience(nil) == :reader
      assert Reading.audience(%{id: 1}) == :admin
    end
  end

  describe "text/2" do
    test "a reader gets the published text of a live entry" do
      article = ran_ahead(title: "Harbor", body: "Old words.")

      read = Reading.text(article, :reader)
      assert read.title == "Harbor"
      assert read.body == "Old words."
    end

    test "an admin gets the working copy" do
      article = ran_ahead()

      seen = Reading.text(article, :admin)
      assert seen.title == "Rewritten"
      assert seen.body == "New words."
    end

    test "a draft has one text only, whoever asks" do
      draft = draft_post(title: "Draft", body: "Only words.")

      assert Reading.text(draft, :reader).title == "Draft"
      assert Reading.text(draft, :admin).title == "Draft"
    end

    test "a list is answered entry by entry" do
      ahead = ran_ahead(title: "Harbor")
      plain = published_post(title: "Plain")

      titles = [ahead, plain] |> Reading.text(:reader) |> Enum.map(& &1.title)
      assert titles == ["Harbor", "Plain"]
    end
  end

  describe "pending?/2" do
    test "an admin is owed the strip when the working copy ran ahead" do
      assert Reading.pending?(ran_ahead(), :admin)
      refute Reading.pending?(published_post(), :admin)
    end

    test "a reader is never owed a strip" do
      refute Reading.pending?(ran_ahead(), :reader)
    end
  end

  describe "post/3" do
    test "a reader finds a published post at its date and slug" do
      post = published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-08-23])

      assert Reading.post(~D[2026-08-23], "harbor", :reader).id == post.id
    end

    test "another day is another address, and no text" do
      published_post(title: "Harbor", slug: "harbor", publish_date: ~D[2026-08-23])

      assert Reading.post(~D[2026-08-22], "harbor", :reader) == nil
      assert Reading.post(~D[2026-08-22], "harbor", :admin) == nil
    end

    test "a reader gets nil for pages, drafts, scheduled texts and unknown addresses" do
      page = published_page(title: "About", slug: "about-us", publish_date: ~D[2026-08-23])
      draft_post(title: "Draft", slug: "draft-text")
      scheduled = scheduled_post(title: "Scheduled")

      assert Reading.post(page.publish_date, "about-us", :reader) == nil
      assert Reading.post(~D[2026-08-23], "draft-text", :reader) == nil
      assert Reading.post(scheduled.publish_date, scheduled.slug, :reader) == nil
      assert Reading.post(~D[2026-08-23], "nowhere", :reader) == nil
    end

    test "an admin finds a scheduled post at the address it will wear" do
      scheduled = scheduled_post(title: "Scheduled")

      assert Reading.post(scheduled.publish_date, scheduled.slug, :admin).id == scheduled.id
    end

    test "an admin finds a dateless draft under today, and only under today" do
      draft = draft_post(title: "Draft", slug: "draft-text")
      today = Date.utc_today()

      assert Reading.post(today, "draft-text", :admin).id == draft.id
      assert Reading.post(Date.add(today, 1), "draft-text", :admin) == nil
      assert Reading.post(today, "draft-text", :reader) == nil
    end
  end

  describe "page/2" do
    test "a reader finds a published page by its address" do
      page = published_page(title: "About", slug: "about-us")

      assert Reading.page("about-us", :reader).id == page.id
    end

    test "a reader gets nil for posts, drafts and unknown addresses" do
      published_post(title: "Harbor", slug: "harbor")
      draft_post(title: "Draft", slug: "draft-page", type: "page")

      assert Reading.page("harbor", :reader) == nil
      assert Reading.page("draft-page", :reader) == nil
      assert Reading.page("nowhere", :reader) == nil
    end

    test "an admin finds a draft page at the address it will wear" do
      draft = draft_post(title: "Draft", slug: "draft-page", type: "page")

      assert Reading.page("draft-page", :admin).id == draft.id
    end
  end
end
