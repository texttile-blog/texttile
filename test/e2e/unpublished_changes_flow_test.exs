defmodule TexttileWeb.E2E.UnpublishedChangesFlowTest do
  @moduledoc """
  Writing in an entry that is already out.

  The words on the screen and the words on the site are two things
  from the moment an entry goes live. This walks the way between them:
  the bar says which of the two is on the screen, the button hands the
  new one over, and the readers only ever get what was handed over.
  """

  use TexttileWeb.E2E

  alias Texttile.Articles

  describe "the bar over a live entry" do
    test "says the entry is being rewritten, and hands the words over", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      session =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> assert_has("#stateWord", text: "Published")
        |> assert_has("#stateMain", text: "View")
        |> fill_in("Title", with: "Harbor evenings")
        |> assert_has("#stateWord", text: "Live · draft")
        |> assert_has("#stateMain", text: "Publish changes")

      # the readers still have the published title
      assert Articles.as_read(Articles.get_article!(article.id)).title == "Harbor mornings"

      session
      |> click_button("#stateMain", "Publish changes")
      |> assert_has("#stateWord", text: "Published")
      |> assert_has("#stateMain", text: "View")

      assert Articles.as_read(Articles.get_article!(article.id)).title == "Harbor evenings"
    end

    test "the way out of a rewrite is in the menu, and it asks first", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> fill_in("Title", with: "Harbor evenings")
      |> assert_has("#stateWord", text: "Live · draft")
      |> click("#stateChev")
      |> click_button("#discardChangesRow", "Discard the changes")
      |> click_button("Discard the changes")
      |> assert_has("#edTitle[value='Harbor mornings']")
      |> assert_has("#stateWord", text: "Published")
    end

    test "the Versions tab says which version the readers have", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> fill_in("Title", with: "Harbor evenings")
      |> click_button("#stateMain", "Publish changes")
      |> click_button(".tab", "Versions")
      |> assert_has(".is-live", text: "live")
      |> assert_has(".is-live", count: 1)
    end
  end

  describe "the reader's side" do
    test "keeps the published text while the entry is being rewritten", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      # written, not published
      conn
      |> sign_in()
      |> open_editor(article.id)
      |> fill_in("Title", with: "Harbor evenings")
      |> assert_has("#stateWord", text: "Live · draft")

      # signed in, the site shows the working copy and says so
      conn
      |> open_page(Articles.public_path(article))
      |> assert_has("h1", text: "Harbor evenings")
      |> assert_has("#unpublished", text: "working copy")
    end

    test "a reader gets the published text and no banner", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings"})

      # this browser never signs in
      conn
      |> open_page(Articles.public_path(article))
      |> assert_has("h1", text: "Harbor mornings")
      |> refute_has("#unpublished")

      conn
      |> open_page("/blog")
      |> assert_has("a", text: "Harbor mornings")
      |> refute_has("a", text: "Harbor evenings")
    end
  end

  describe "the overviews name the author" do
    test "beside the day, in the admin area and on the reader's side", %{conn: conn, kb: kb} do
      {:ok, kb} = Texttile.Accounts.update_display_name(kb, "Klaus Breyer")
      article = published_post(user: kb, title: "Harbor mornings")

      conn
      |> sign_in()
      |> open("/admin/texts")
      |> assert_has(".card .cm", text: "Klaus Breyer")

      conn
      |> open_page("/blog")
      |> assert_has(".card-wrap .cm", text: "Klaus Breyer")
      |> open_page(Articles.public_path(article))
      |> assert_has("#by", text: "Klaus Breyer")
    end
  end
end
