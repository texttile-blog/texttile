defmodule Texttile.TagsTest do
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures
  alias Texttile.Articles

  test "renaming changes every state and case variant, but no text or versions" do
    entries = [
      draft_post(tags: "reisen, Meer", body: "  Original\n\nMarkdown  "),
      published_post(tags: "Reisen, Fotografie"),
      scheduled_post(tags: "REISEN"),
      published_page(tags: "reisen")
    ]

    untouched = draft_post(tags: "Weltreisen, Meer")
    histories = Map.new(entries, &{&1.id, Articles.versions(&1)})
    Articles.subscribe_admin()
    Articles.subscribe(hd(entries).id)

    assert {:ok, 4} = Articles.rename_tag("reisen", " Reisen ")

    for before <- entries do
      after_rename = Articles.get_article!(before.id)
      assert hd(Articles.tag_list(after_rename)) == "Reisen"
      assert after_rename.body == before.body
      assert after_rename.title == before.title
      assert after_rename.status == before.status
      assert after_rename.live_version_id == before.live_version_id
      assert Articles.versions(after_rename) == histories[before.id]
      id = before.id
      assert_receive {:article_changed, %{id: ^id}}
    end

    id = hd(entries).id
    assert_receive {:article_changed, %{id: ^id}}
    assert Articles.get_article!(untouched.id).tags == untouched.tags
    assert {"Reisen", 4} in Articles.tag_counts()
    assert "Reisen" in Articles.known_tags()
    assert {:ok, 4} = Articles.rename_tag("REISEN", "Unterwegs")
    assert {:ok, 4} = Articles.rename_tag("Unterwegs", "reisen")
  end

  test "matching handles Unicode, literal wildcard characters and whole tags" do
    one = draft_post(tags: "ÜBER, Meer")
    two = draft_post(tags: "über, Übermorgen")
    assert {:ok, 2} = Articles.rename_tag("über", "Über")
    assert Articles.get_article!(one.id).tags == "Über, Meer"
    assert Articles.get_article!(two.id).tags == "Über, Übermorgen"
    assert Articles.delete_tag("ÜBER") == 2
    assert Articles.get_article!(two.id).tags == "Übermorgen"

    literal = draft_post(tags: "100%, a_b, aXb")
    assert {:ok, 1} = Articles.rename_tag("100%", "Alles")
    assert {:ok, 1} = Articles.rename_tag("a_b", "Unterstrich")
    assert Articles.get_article!(literal.id).tags == "Alles, Unterstrich, aXb"
  end

  test "empty, comma-separated and existing names do not change entries" do
    one = draft_post(tags: "reisen, Meer")
    draft_post(tags: "Fotografie")

    for invalid <- ["", "  ", "Reisen, Meer"] do
      assert {:error, :invalid_tag} = Articles.rename_tag("reisen", invalid)
    end

    assert {:error, :tag_exists} = Articles.rename_tag("reisen", "FOTOGRAFIE")
    assert {:error, :not_found} = Articles.rename_tag("missing", "Reisen")
    assert Articles.get_article!(one.id).tags == "reisen, Meer"
  end

  test "counts group case variants and retain the first spelling" do
    draft_post(tags: "Reisen, reisen, Meer")
    draft_post(tags: "REISEN")
    assert Articles.tag_counts() == [{"Reisen", 2}, {"Meer", 1}]
    assert Articles.tag_list(%{tags: "Reisen, REISEN, Meer"}) == ["Reisen", "Meer"]
  end
end
