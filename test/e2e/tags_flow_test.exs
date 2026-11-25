defmodule TexttileWeb.E2E.TagsFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

  test "digit 4 opens Tags and a rename reaches every entry and the reader", %{conn: conn} do
    live = published_post(tags: "reisen, Meer")
    draft = draft_post(tags: "REISEN")
    blank = draft_post()

    session =
      conn
      |> sign_in()
      |> press(by_css("body"), "4")
      |> assert(contain_text(by_css("#crumb"), "Tags"))
      |> click(by_css("#edit-tag-reisen"))
      |> fill(by_label("Name"), "Reisen4")
      |> press(by_css("#tag-name"), "2")
      |> assert(contain_text(by_css("#crumb"), "Tags"))
      |> fill(by_label("Name"), "Reisen")
      |> click(by_role(:button, name: "Rename"))
      |> assert(contain_text(by_css("#tagrow-reisen a"), "Reisen"))
      |> assert(contain_text(by_css("#tagrow-reisen"), "2 entries"))

    assert Articles.get_article!(live.id).tags == "Reisen, Meer"
    assert Articles.get_article!(draft.id).tags == "Reisen"

    session
    |> open_editor(draft.id)
    |> assert_has(by_css("#edTags[value='Reisen']"))
    |> assert(contain_text(by_css("#tagchip-reisen.on"), "Reisen"))
    |> open_editor(blank.id)
    |> press_sequentially(by_css("#edTags"), "rei")
    |> assert(contain_text(by_css(~s(#tagMenu li[data-tag="Reisen"])), "Reisen"))
    |> press(by_css("#edTags"), "Enter")
    |> assert(contain_text(by_css("#tagchip-reisen.on"), "Reisen"))
    |> open_page("/tags/reisen")
    |> assert(contain_text(by_css("#title"), "#Reisen"))
  end

  test "cancel, invalid rename and delete keep their distinct outcomes", %{conn: conn} do
    entry = draft_post(tags: "reisen, Meer")

    session =
      conn
      |> sign_in()
      |> open("/admin/tags")
      |> click(by_css("#edit-tag-reisen"))
      |> fill(by_label("Name"), "Meer")
      |> click(by_role(:button, name: "Rename"))
      |> assert(contain_text(by_css("#tag-error"), "already exists"))
      |> click(by_css("#cancel-tag-edit"))
      |> refute_has(by_css("#rename-tag-form"))
      |> click(by_css("#delete-tag-reisen"))
      |> click(by_css("#dialog-cancel"))
      |> assert_has(by_css("#tagrow-reisen"))

    assert Articles.get_article!(entry.id).tags == "reisen, Meer"

    session
    |> click(by_css("#delete-tag-reisen"))
    |> click(by_css("#dialog-ok"))
    |> refute_has(by_css("#tagrow-reisen"))
    |> assert_has(by_css("#tagrow-meer"))

    assert Articles.get_article!(entry.id).tags == "Meer"
  end
end
