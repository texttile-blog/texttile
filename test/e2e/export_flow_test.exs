defmodule TexttileWeb.E2E.ExportFlowTest do
  @moduledoc """
  The way to a copy of one entry: the row in the menu of the editor,
  and the mark on the card in the list.

  A zip does not arrive in the page, so the test asks the browser to
  fetch the address the control carries. That goes out with the session
  of the signed-in admin, which is what the control does when it is
  clicked.
  """
  use TexttileWeb.E2E

  # What the browser gets back from the address of the control: the
  # answer code, what it says the file is, and whether anything came.
  @fetched """
  async (address) => {
    const answer = await fetch(address);
    const file = await answer.blob();
    return [answer.status, answer.headers.get("content-type"), file.size > 0];
  }
  """

  test "the editor menu hands the entry out as a zip", %{conn: conn, kb: kb} do
    article = draft!(kb, "Beach days", "Plain words.")
    {:ok, article} = Texttile.Articles.update_settings(article, %{slug: "beach-days"})

    session =
      conn
      |> sign_in()
      |> open_editor(article.id)
      |> click("#stateChev")
      |> assert_has("#exportRow", text: "Export as a zip")

    address = "/admin/texts/#{article.id}/export"

    evaluate(session, @fetched, [arg: address, is_function: true], fn answer ->
      assert answer == [200, "application/zip", true]
    end)
  end

  test "every card in the list carries the same way out", %{conn: conn, kb: kb} do
    article = draft!(kb, "Beach days", "Plain words.")

    conn
    |> sign_in()
    |> open("/admin/texts")
    |> assert_has("#export-#{article.id}[href='/admin/texts/#{article.id}/export']")
  end
end
