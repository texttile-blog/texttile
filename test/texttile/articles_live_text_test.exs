defmodule Texttile.ArticlesLiveTextTest do
  @moduledoc """
  The two texts of a live entry: the working copy in the editor, and
  the version the readers have.

  Until now a keystroke in a published entry was on the site the same
  second, so a half-written sentence was published by writing it. From
  here the entry keeps both, and only a publish moves the second one.
  """

  use Texttile.DataCase

  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  setup do
    %{user: Texttile.AccountsFixtures.user_fixture()}
  end

  describe "what a reader gets" do
    test "a draft has one text, and it is the one that is written", %{user: user} do
      article = draft_post(user: user, title: "Half a thought", body: "Not finished.")

      read = Articles.as_read(article)
      assert read.title == "Half a thought"
      assert read.body == "Not finished."
      refute Articles.unpublished_changes?(article)
    end

    test "publishing hands the readers the words as they stand", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", body: "Fog over the pier.")

      read = article.id |> Articles.get_article!() |> Articles.as_read()
      assert read.title == "Harbor mornings"
      assert read.body == "Fog over the pier."
    end

    test "a keystroke after that moves the working copy and nothing else", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings", body: "Rain now."})

      article = Articles.get_article!(article.id)

      # the editor sees what was typed
      assert article.title == "Harbor evenings"
      assert article.body == "Rain now."

      # the readers do not
      read = Articles.as_read(article)
      assert read.title == "Harbor mornings"
      assert read.body == "Fog over the pier."

      assert Articles.unpublished_changes?(article)
      assert article.id in Articles.entries_with_unpublished_changes()
    end

    test "the tags and the address are one thing and go over at once", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", tags: "sea")
      {:ok, _} = Articles.update_settings(article, %{"tags" => "sea, fog"})

      read = article.id |> Articles.get_article!() |> Articles.as_read()
      assert read.tags == "sea, fog"
    end
  end

  describe "publish_changes/2" do
    test "hands the working copy to the readers, and moves nothing else", %{user: user} do
      article =
        published_post(user: user, title: "Harbor mornings", publish_date: ~D[2026-01-05])

      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings"})
      article = Articles.get_article!(article.id)

      {:ok, article} = Articles.publish_changes(article, user)

      assert Articles.as_read(article).title == "Harbor evenings"
      refute Articles.unpublished_changes?(article)
      assert article.status == "published"
      assert article.publish_date == ~D[2026-01-05]
    end

    test "an entry nobody has touched has nothing to hand over", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings")
      assert Articles.publish_changes(Articles.get_article!(article.id), user) == :unchanged
    end

    test "writes a line in the Log, and the version it published", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings")
      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings"})

      {:ok, article} =
        article.id |> Articles.get_article!() |> Articles.publish_changes(user)

      assert Enum.any?(Articles.log(article), &(&1.text == "published the changes"))
      assert Enum.any?(Articles.versions(article), &(&1.title == "Harbor evenings"))
    end
  end

  describe "discard_changes/2" do
    test "puts the published words back and keeps the discarded ones", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings", body: "Rain now."})

      {:ok, article} =
        article.id |> Articles.get_article!() |> Articles.discard_changes(user)

      assert article.title == "Harbor mornings"
      assert article.body == "Fog over the pier."
      refute Articles.unpublished_changes?(article)

      # nothing written is finally lost: the discarded text is a version
      assert Enum.any?(Articles.versions(article), &(&1.body == "Rain now."))
    end

    test "an entry that says what the readers have has nothing to throw away", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings")
      assert Articles.discard_changes(Articles.get_article!(article.id), user) == :unchanged
    end
  end

  describe "the states around it" do
    test "unpublishing and publishing again hands over what stands then", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings")
      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings"})

      {:ok, article} = article.id |> Articles.get_article!() |> Articles.unpublish(user)
      refute Articles.unpublished_changes?(article)

      {:ok, article} = Articles.publish(article, user)
      assert Articles.as_read(article).title == "Harbor evenings"
    end

    test "a scheduled entry has no readers yet, so it has nothing held back", %{user: user} do
      article = scheduled_post(user: user, title: "Later")
      refute Articles.unpublished_changes?(article)
      assert Articles.as_read(article).title == "Later"
    end

    # Nobody is at the keyboard when a scheduled entry goes out, so the
    # go-live has to hand the words over by itself. Without that the
    # entry would be live with nothing published behind it, and every
    # keystroke after it would be on the site again.
    test "a go-live hands over the words that stand that morning", %{user: user} do
      day = Date.add(Date.utc_today(), 3)
      article = scheduled_post(user: user, title: "Later", publish_date: day)
      {:ok, _} = Articles.update_text(article, %{title: "Later, corrected"})

      [live] = Articles.go_live_due(day)
      assert Articles.as_read(live).title == "Later, corrected"

      {:ok, _} = Articles.update_text(live, %{title: "Written after it went out"})
      article = Articles.get_article!(article.id)
      assert Articles.as_read(article).title == "Later, corrected"
      assert Articles.unpublished_changes?(article)
    end

    test "a date dragged onto today hands the words over too", %{user: user} do
      article = scheduled_post(user: user, title: "Later")
      {:ok, article} = Articles.set_publish_date(article, user, Date.utc_today())

      assert article.status == "published"
      assert Articles.as_read(article).title == "Later"
      refute Articles.unpublished_changes?(Articles.get_article!(article.id))
    end

    test "a restore writes the working copy, not the site", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{body: "Rain now."})
      article = Articles.get_article!(article.id)
      {:ok, _} = Articles.publish_changes(article, user)

      article = Articles.get_article!(article.id)
      [_newest, older] = Articles.versions(article)
      {:ok, article} = Articles.restore_version(article, older, user)

      assert article.body == "Fog over the pier."
      # the readers still have what was published
      assert Articles.as_read(article).body == "Rain now."
      assert Articles.unpublished_changes?(article)
    end
  end

  describe "the search and the feed read the published text" do
    test "the field finds the words a reader can see, not the ones being written",
         %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{body: "Sandstorm over the dunes."})

      assert Articles.list_published(search: "fog") != []
      assert Articles.list_published(search: "sandstorm") == []
    end

    test "the feed carries the published text", %{user: user} do
      article = published_post(user: user, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{title: "Not out yet"})

      rss = Texttile.Feed.rss("https://example.org")
      assert rss =~ "Harbor mornings"
      refute rss =~ "Not out yet"
    end
  end
end
