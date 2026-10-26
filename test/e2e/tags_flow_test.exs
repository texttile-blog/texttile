defmodule TexttileWeb.E2E.TagsFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

  test "digit 4 opens Tags and a rename reaches every entry and the reader", %{conn: conn} do
    live = published_post(tags: "reisen, Meer")
    draft = draft_post(tags: "REISEN")

    session =
      conn
      |> sign_in()
      |> press("body", "4")
      |> await_live()
      |> assert_has("#crumb", text: "Tags")
      |> click_button("#edit-tag-reisen", "Edit")
      |> fill_in("Name", with: "Reisen4")
      |> press("#tag-name", "2")
      |> assert_has("#crumb", text: "Tags")
      |> fill_in("Name", with: "Reisen")
      |> click_button("Rename")
      |> assert_has("#tagrow-reisen b", text: "Reisen")
      |> assert_has("#tagrow-reisen", text: "2 entries")

    assert Articles.get_article!(live.id).tags == "Reisen, Meer"
    assert Articles.get_article!(draft.id).tags == "Reisen"

    session
    |> open_editor(draft.id)
    |> assert_has("#edTags[value='Reisen']")
    |> assert_has("#tagchip-reisen.on", text: "Reisen")
    |> open_page("/tags/reisen")
    |> assert_has("#title", text: "#Reisen")
  end

  test "cancel, invalid rename and delete keep their distinct outcomes", %{conn: conn} do
    entry = draft_post(tags: "reisen, Meer")

    session =
      conn
      |> sign_in()
      |> open("/admin/tags")
      |> click_button("#edit-tag-reisen", "Edit")
      |> fill_in("Name", with: "Meer")
      |> click_button("Rename")
      |> assert_has("#tag-error", text: "already exists")
      |> click_button("#cancel-tag-edit", "Cancel")
      |> refute_has("#rename-tag-form")
      |> click_button("#delete-tag-reisen", "Delete")
      |> click_button("#dialog-cancel", "Cancel")
      |> assert_has("#tagrow-reisen")

    assert Articles.get_article!(entry.id).tags == "reisen, Meer"

    session
    |> click_button("#delete-tag-reisen", "Delete")
    |> click_button("#dialog-ok", "Delete the tag")
    |> refute_has("#tagrow-reisen")
    |> assert_has("#tagrow-meer")

    assert Articles.get_article!(entry.id).tags == "Meer"
  end
end
