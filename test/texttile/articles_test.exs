defmodule Texttile.ArticlesTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles

  @today ~D[2026-08-04]

  defp draft(attrs \\ %{}) do
    user = user_fixture()
    {:ok, article} = Articles.create_draft(user)

    article =
      if attrs == %{} do
        article
      else
        {:ok, article} = Articles.update_text(article, attrs)
        article
      end

    {article, user}
  end

  describe "create_draft/1" do
    test "starts empty, as a draft post" do
      {article, _user} = draft()
      assert article.title == ""
      assert article.body == ""
      assert article.status == "draft"
      assert article.type == "post"
      assert article.slug == nil
      assert article.publish_date == nil
      assert article.allow_comments
      assert article.notify_on_publish
    end

    test "writes the first log line" do
      {article, user} = draft()
      assert [entry] = Articles.log(article)
      assert entry.user_id == user.id
      assert entry.text =~ "started"
    end
  end

  describe "update_text/2 (autosave)" do
    test "stores title and body without touching the log" do
      {article, _user} = draft()
      {:ok, article} = Articles.update_text(article, %{title: "Doors", body: "Fourteen of them."})
      assert article.title == "Doors"
      assert article.body == "Fourteen of them."
      assert length(Articles.log(article)) == 1
    end
  end

  describe "slugify/1" do
    test "lowercases and dashes" do
      assert Articles.slugify("Fourteen doors of Vilnius!") == "fourteen-doors-of-vilnius"
      assert Articles.slugify("  ") == ""
      assert Articles.slugify("Ä ö ü") == ""
    end
  end

  describe "publish/3" do
    test "an empty or past date publishes today" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.publish(article, user, today: @today)
      assert article.status == "published"
      assert article.publish_date == @today
      assert article.slug == "doors"
    end

    test "a future date in the settings schedules instead" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-09-01], today: @today)
      assert article.status == "draft"

      {:ok, article} = Articles.publish(article, user, today: @today)
      assert article.status == "scheduled"
      assert article.publish_date == ~D[2026-09-01]
    end

    test "force publishes a scheduled text now" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-09-01], today: @today)
      {:ok, article} = Articles.publish(article, user, today: @today)
      {:ok, article} = Articles.publish(article, user, today: @today, force: true)
      assert article.status == "published"
      assert article.publish_date == @today
    end

    test "an untitled draft still gets a slug" do
      {article, user} = draft()
      {:ok, article} = Articles.publish(article, user, today: @today)
      assert article.slug == "untitled"
    end

    test "a taken slug gets a numbered one" do
      {a1, user} = draft(%{title: "Doors", body: "x"})
      {:ok, _} = Articles.publish(a1, user, today: @today)
      {a2, user2} = draft(%{title: "Doors", body: "y"})
      {:ok, a2} = Articles.publish(a2, user2, today: @today)
      assert a2.slug == "doors-2"
    end

    test "publishing writes a version snapshot" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.publish(article, user, today: @today)
      assert [version] = Articles.versions(article)
      assert version.title == "Doors"
      assert version.body == "x"
    end
  end

  describe "unpublish/2" do
    test "published back to draft, date cleared" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.publish(article, user, today: @today)
      {:ok, article} = Articles.unpublish(article, user)
      assert article.status == "draft"
      assert article.publish_date == nil
    end
  end

  describe "set_publish_date/4" do
    test "clearing the date of a live text unpublishes it" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.publish(article, user, today: @today)
      {:ok, article} = Articles.set_publish_date(article, user, nil, today: @today)
      assert article.status == "draft"
    end

    test "a future date on a published text schedules it again" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.publish(article, user, today: @today)
      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-09-01], today: @today)
      assert article.status == "scheduled"
    end

    test "a date on a draft stays a draft" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-09-01], today: @today)
      assert article.status == "draft"
      assert article.publish_date == ~D[2026-09-01]
    end
  end

  describe "go_live_due/1" do
    test "flips scheduled texts whose day has come" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-08-05], today: @today)
      {:ok, article} = Articles.publish(article, user, today: @today)
      assert article.status == "scheduled"

      assert Articles.go_live_due(~D[2026-08-04]) == []
      assert [gone_live] = Articles.go_live_due(~D[2026-08-05])
      assert gone_live.id == article.id
      assert Articles.get_article!(article.id).status == "published"
    end
  end

  describe "versions" do
    test "save_version stores title and body" do
      {article, user} = draft(%{title: "Doors", body: "First."})
      {:ok, _} = Articles.save_version(article, user)
      assert [version] = Articles.versions(article)
      assert version.title == "Doors"
      assert version.body == "First."
      assert version.user_id == user.id
    end

    test "a byte-identical save is not a second version" do
      {article, user} = draft(%{title: "Doors", body: "First."})
      {:ok, _} = Articles.save_version(article, user)
      assert :unchanged = Articles.save_version(article, user)
      assert length(Articles.versions(article)) == 1
    end

    test "restore writes the pre-restore state as a version first" do
      {article, user} = draft(%{title: "Doors", body: "First."})
      {:ok, version} = Articles.save_version(article, user)
      {:ok, article} = Articles.update_text(article, %{title: "Doors", body: "Second."})

      {:ok, article} = Articles.restore_version(article, version, user)
      assert article.body == "First."

      bodies = article |> Articles.versions() |> Enum.map(& &1.body)
      assert "Second." in bodies
    end

    test "restore does not touch status, slug or date" do
      {article, user} = draft(%{title: "Doors", body: "First."})
      {:ok, version} = Articles.save_version(article, user)
      {:ok, article} = Articles.publish(article, user, today: @today)
      {:ok, article} = Articles.update_text(article, %{title: "Doors", body: "Second."})

      {:ok, article} = Articles.restore_version(article, version, user)
      assert article.status == "published"
      assert article.slug == "doors"
      assert article.publish_date == @today
    end
  end

  describe "diff/2" do
    test "marks added and removed words" do
      diff = Articles.diff("the quick fox", "the slow fox")
      assert {:del, "quick"} in diff
      assert {:add, "slow"} in diff
      assert {:same, "the"} in diff
    end

    test "identical texts are all same" do
      assert [{:same, _}] = Articles.diff("one two", "one two") |> collapse()
    end

    test "a long text with a small edit still gets a real diff" do
      long = Enum.map_join(1..2000, " ", &"word#{&1}")
      changed = String.replace(long, "word1000", "changed1000")

      diff = Articles.diff(long, changed)
      assert {:del, "word1000"} in diff
      assert {:add, "changed1000"} in diff
      assert Enum.count(diff, &(elem(&1, 0) != :same)) == 2
    end

    defp collapse(diff) do
      diff
      |> Enum.chunk_by(fn {kind, _} -> kind end)
      |> Enum.map(fn chunk ->
        {kind, _} = hd(chunk)
        {kind, chunk |> Enum.map(fn {_, text} -> text end) |> Enum.join()}
      end)
    end
  end

  describe "list and search" do
    test "filter by status, search in title, tags and body" do
      {a1, user} = draft(%{title: "Doors of Vilnius", body: "wooden doors"})
      {:ok, a1} = Articles.update_settings(a1, %{tags: "travel, doors"})
      {:ok, _} = Articles.publish(a1, user, today: @today)
      {_a2, _} = draft(%{title: "Slow trains", body: "a week on rails"})

      assert length(Articles.list_articles()) == 2
      assert [%{title: "Doors of Vilnius"}] = Articles.list_articles(filter: "published")
      assert [%{title: "Slow trains"}] = Articles.list_articles(filter: "draft")
      assert [%{title: "Doors of Vilnius"}] = Articles.list_articles(search: "wooden")
      assert [%{title: "Doors of Vilnius"}] = Articles.list_articles(search: "travel")
      assert [%{title: "Slow trains"}] = Articles.list_articles(search: "TRAINS")
    end

    test "the grid stands by date, newest first" do
      {old, user} = draft(%{title: "Old"})
      {:ok, _} = Articles.publish(old, user, today: ~D[2019-04-05])

      {recent, user} = draft(%{title: "Recent"})
      {:ok, _} = Articles.publish(recent, user, today: ~D[2024-11-12])

      {middle, user} = draft(%{title: "Middle"})
      {:ok, _} = Articles.publish(middle, user, today: ~D[2021-08-01])

      assert Enum.map(Articles.list_articles(), & &1.title) == ["Recent", "Middle", "Old"]
    end

    test "a draft has no date yet and stands on top" do
      {published, user} = draft(%{title: "Live"})
      {:ok, _} = Articles.publish(published, user, today: @today)
      {_open, _} = draft(%{title: "Still writing"})

      assert ["Still writing" | _] = Enum.map(Articles.list_articles(), & &1.title)
    end
  end

  describe "inline_refs/1" do
    test "reads finished images, running uploads and failed ones from the body" do
      body = """
      Some prose.

      ![pier](/uploads/images/pier-abcd.jpg)

      ![Uploading gull.jpg…]()

      ![Upload failed: fog.png]()

      ![decorative]()
      """

      assert [
               %{kind: :done, file: "pier-abcd.jpg", url: "/uploads/images/pier-abcd.jpg"},
               %{kind: :running, file: "gull.jpg"},
               %{kind: :failed, file: "fog.png"}
             ] = Articles.inline_refs(body)
    end

    test "an empty body has no references" do
      assert Articles.inline_refs("") == []
      assert Articles.inline_refs(nil) == []
    end
  end

  describe "delete_article/1" do
    test "versions and log go with the text" do
      {article, user} = draft(%{title: "Doors", body: "x"})
      {:ok, _} = Articles.save_version(article, user)
      {:ok, _} = Articles.delete_article(article)
      assert Articles.list_articles() == []
      assert Repo.aggregate(Texttile.Articles.Version, :count) == 0
      assert Repo.aggregate(Texttile.Articles.LogEntry, :count) == 0
    end

    test "the images in the body go with the text, old versions included" do
      alias Texttile.Uploads
      File.rm_rf!(Uploads.root())

      current = "images/door-aaaa1111.png"
      versioned = "images/gone-bbbb2222.png"

      for relative <- [current, versioned] do
        path = Uploads.absolute(relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, "png bytes")
      end

      {article, user} = draft(%{title: "Doors", body: "![gone](/uploads/#{versioned})"})
      {:ok, _} = Articles.save_version(article, user)
      {:ok, article} = Articles.update_text(article, %{body: "![door](/uploads/#{current})"})

      {:ok, _} = Articles.delete_article(article)

      refute File.exists?(Uploads.absolute(current))
      refute File.exists?(Uploads.absolute(versioned))
    end
  end

  describe "tags" do
    test "tag_counts/0 counts the texts on each tag, the busiest first" do
      {one, _} = draft()
      {two, _} = draft()
      {:ok, _} = Articles.update_settings(one, %{tags: "sea, fog"})
      {:ok, _} = Articles.update_settings(two, %{tags: "Sea"})

      assert Articles.tag_counts() == [{"sea", 2}, {"fog", 1}]
      assert Articles.known_tags() == ["sea", "fog"]
    end

    test "delete_tag/1 takes the tag off every text and leaves the rest" do
      {one, _} = draft()
      {two, _} = draft()
      {three, _} = draft()
      {:ok, _} = Articles.update_settings(one, %{tags: "sea, fog"})
      {:ok, _} = Articles.update_settings(two, %{tags: "Sea"})
      {:ok, _} = Articles.update_settings(three, %{tags: "doors"})

      assert Articles.delete_tag("sea") == 2

      assert Articles.get_article!(one.id).tags == "fog"
      assert Articles.get_article!(two.id).tags == ""
      assert Articles.get_article!(three.id).tags == "doors"
      assert Articles.known_tags() == ["doors", "fog"]
    end

    test "delete_tag/1 leaves a tag that only holds the word inside it" do
      {one, _} = draft()
      {:ok, _} = Articles.update_settings(one, %{tags: "seawall, sea"})

      assert Articles.delete_tag("sea") == 1
      assert Articles.get_article!(one.id).tags == "seawall"
    end

    test "delete_tag/1 answers zero for a tag no text carries" do
      {one, _} = draft()
      {:ok, _} = Articles.update_settings(one, %{tags: "sea"})

      assert Articles.delete_tag("harbor") == 0
      assert Articles.delete_tag("  ") == 0
      assert Articles.get_article!(one.id).tags == "sea"
    end
  end
end
