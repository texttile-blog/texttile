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

  test "two marks clicked one after the other give two downloads, and both say so",
       %{conn: conn, kb: kb} do
    one = draft!(kb, "One", "Plain words.")
    {:ok, one} = Texttile.Articles.update_settings(one, %{slug: "one"})
    two = draft!(kb, "Two", "Plain words.")
    {:ok, two} = Texttile.Articles.update_settings(two, %{slug: "two"})

    session =
      conn
      |> sign_in()
      |> open("/admin/texts")
      |> click("#export-#{one.id}")
      |> click("#export-#{two.id}")
      |> assert_has("#export-#{one.id}.sent")
      |> assert_has("#export-#{two.id}.sent")

    # The second click does not cancel the first: each export runs in a
    # frame of its own, so both arrive.
    names =
      for _ <- 1..2 do
        PhoenixTest.Playwright.assert_download(session, &send(self(), {:name, &1.name}))
        assert_received {:name, name}
        name
      end

    assert Enum.sort(names) == ["one.zip", "two.zip"]
  end

  test "an export that fails says so on its mark", %{conn: conn, kb: kb} do
    article = draft!(kb, "Gone soon", "Plain words.")

    session =
      conn
      |> sign_in()
      |> open("/admin/texts")

    # The entry goes behind the page's back, so the export answers 404.
    Texttile.Repo.delete!(article)

    session
    |> click("#export-#{article.id}")
    |> assert_has("#export-#{article.id}.failed")
  end
end
