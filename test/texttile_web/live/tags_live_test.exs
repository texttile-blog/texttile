defmodule TexttileWeb.TagsLiveTest do
  use TexttileWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures
  alias Texttile.Articles

  setup :register_and_log_in_user

  describe "tags" do
    setup %{user: user} do
      {:ok, one} = Articles.create_draft(user)
      {:ok, two} = Articles.create_draft(user)
      {:ok, one} = Articles.update_settings(one, %{tags: "sea, fog"})
      {:ok, two} = Articles.update_settings(two, %{tags: "sea"})
      %{one: one, two: two}
    end

    test "lists every tag with the number of texts on it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      assert has_element?(view, "#tagrow-sea", "sea")
      assert has_element?(view, "#tagrow-sea", "2 entries")
      assert has_element?(view, "#tagrow-fog", "1 entry")
    end

    test "deleting a tag asks first, then takes it off every text",
         %{conn: conn, one: one, two: two} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      view |> element("#delete-tag-sea") |> render_click()
      assert has_element?(view, "#dialog-ok")

      view |> element("#dialog-ok") |> render_click()

      assert Articles.get_article!(one.id).tags == "fog"
      assert Articles.get_article!(two.id).tags == ""
      refute has_element?(view, "#tagrow-sea")
      assert has_element?(view, "#tagrow-fog")
      assert has_element?(view, "#flash-info")
    end

    test "the way out of the question leaves every tag where it is",
         %{conn: conn, one: one} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      view |> element("#delete-tag-sea") |> render_click()
      view |> element("#dialog-cancel") |> render_click()

      refute has_element?(view, "#dialog-ok")
      assert Articles.get_article!(one.id).tags == "sea, fog"
      assert has_element?(view, "#tagrow-sea")
    end

    test "a blog without tags says so", %{conn: conn, one: one, two: two} do
      {:ok, _} = Articles.update_settings(one, %{tags: ""})
      {:ok, _} = Articles.update_settings(two, %{tags: ""})

      assert Articles.tag_counts() == []

      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      assert has_element?(view, "#tagsList", "No entry carries a tag yet")
    end
  end

  test "readers cannot open tag administration" do
    conn = get(build_conn(), "/admin/tags")
    assert redirected_to(conn) =~ "/login"
  end

  test "two admins see renames and open editors retain their body", %{conn: conn, user: user} do
    entry = draft_post(user: user, tags: "reisen", body: "Original body")
    other = Texttile.AccountsFixtures.user_fixture()
    other_conn = log_in_user(build_conn(), other)
    {:ok, editor, _} = live(conn, "/admin/texts/#{entry.id}")
    {:ok, watcher, _} = live(other_conn, "/admin/texts/#{entry.id}")
    blank = draft_post(user: user)
    {:ok, suggestions, _} = live(conn, "/admin/texts/#{blank.id}")
    {:ok, tags, _} = live(conn, "/admin/tags")
    {:ok, other_tags, _} = live(other_conn, "/admin/tags")

    tags |> element("#edit-tag-reisen") |> render_click()
    tags |> form("#rename-tag-form", tag: %{name: "Reisen"}) |> render_submit()

    for view <- [tags, other_tags] do
      assert has_element?(view, "#tagrow-reisen b", "Reisen")
    end

    for view <- [editor, watcher] do
      assert has_element?(view, ~s(#edTags[value="Reisen"]))
      assert has_element?(view, "#tagchip-reisen.on", "Reisen")
    end

    assert has_element?(suggestions, "#tagchip-reisen", "Reisen")
    refute has_element?(suggestions, "#tagchip-reisen.on")
    assert Articles.get_article!(entry.id).body == "Original body"
  end

  test "a remote rename closes an obsolete edit without recreating its tag", %{conn: conn} do
    draft_post(tags: "reisen")
    {:ok, view, _} = live(conn, "/admin/tags")
    view |> element("#edit-tag-reisen") |> render_click()
    assert {:ok, 1} = Articles.rename_tag("reisen", "Unterwegs")
    refute has_element?(view, "#rename-tag-form")
    assert has_element?(view, "#tagrow-unterwegs", "Unterwegs")
    assert has_element?(view, "#flash-info", "changed while you were editing")
  end

  test "a delete dialog follows case changes and closes when its tag disappears", %{conn: conn} do
    entry = draft_post(tags: "travel")
    {:ok, view, _} = live(conn, "/admin/tags")
    view |> element("#delete-tag-travel") |> render_click()

    assert {:ok, 1} = Articles.rename_tag("travel", "Travel")
    assert has_element?(view, "#dialog-ok")

    assert {:ok, 1} = Articles.rename_tag("Travel", "Trips")
    refute has_element?(view, "#dialog-ok")
    assert has_element?(view, "#flash-info", "This tag no longer exists.")
    render_click(view, "delete_tag")
    assert Articles.get_article!(entry.id).tags == "Trips"

    view |> element("#delete-tag-trips") |> render_click()
    assert Articles.delete_tag("Trips") == 1
    refute has_element?(view, "#dialog-ok")
  end

  test "a delete received before the change notification does not report success on zero entries",
       %{conn: conn} do
    entry = draft_post(tags: "travel")
    {:ok, view, _} = live(conn, "/admin/tags")
    view |> element("#delete-tag-travel") |> render_click()

    # Simulate the interval between another admin's commit and its PubSub notification.
    entry |> Ecto.Changeset.change(tags: "Trips") |> Texttile.Repo.update!()
    view |> element("#dialog-ok") |> render_click()

    assert has_element?(view, "#flash-info", "This tag no longer exists.")
    refute has_element?(view, "#dialog-ok")
    assert Articles.get_article!(entry.id).tags == "Trips"
  end
end
