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
        |> assert(text(by_css("#stateWord"), "Live"))
        |> assert(contain_text(by_css("#stateMain"), "View"))
        |> fill(by_label("Title", exact: true), "Harbor evenings")
        |> assert(contain_text(by_css("#stateWord"), "Live · draft"))
        |> assert(contain_text(by_css("#stateMain"), "Publish changes"))

      # the readers still have the published title
      assert Articles.as_read(Articles.get_article!(article.id)).title == "Harbor mornings"

      session
      |> click(by_css("#stateMain"))
      |> assert(text(by_css("#stateWord"), "Live"))
      |> assert(contain_text(by_css("#stateMain"), "View"))

      assert Articles.as_read(Articles.get_article!(article.id)).title == "Harbor evenings"
    end

    test "the way out of a rewrite is in the menu, and it asks first", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> fill(by_label("Title", exact: true), "Harbor evenings")
      |> assert(contain_text(by_css("#stateWord"), "Live · draft"))
      |> click(by_css("#stateChev"))
      |> click(by_css("#discardChangesRow"))
      |> click(by_role(:button, name: "Discard the changes"))
      |> assert_has(by_css("#edTitle[value='Harbor mornings']"))
      |> assert(text(by_css("#stateWord"), "Live"))
    end

    test "the Versions tab says which version the readers have", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> fill(by_label("Title", exact: true), "Harbor evenings")
      |> click(by_css("#stateMain"))
      |> click(by_css(".tab") |> filter(has_text: "Versions"))
      |> assert(contain_text(by_css(".is-live"), "live"))
      |> assert(count(by_css(".is-live"), 1))
    end
  end

  describe "the reader's side" do
    test "keeps the published text while the entry is being rewritten", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")

      # written, not published
      conn
      |> sign_in()
      |> open_editor(article.id)
      |> fill(by_label("Title", exact: true), "Harbor evenings")
      |> assert(contain_text(by_css("#stateWord"), "Live · draft"))

      # signed in, the site shows the working copy and says so
      conn
      |> open_page(Articles.public_path(article))
      |> assert_has(by_role(:heading, level: 1, name: "Harbor evenings"))
      |> assert(contain_text(by_css("#unpublished"), "working copy"))
    end

    test "a reader gets the published text and no banner", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings", body: "Fog over the pier.")
      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings"})

      # this browser never signs in
      conn
      |> open_page(Articles.public_path(article))
      |> assert_has(by_role(:heading, level: 1, name: "Harbor mornings"))
      |> refute_has(by_css("#unpublished"))

      conn
      |> open_page("/blog")
      |> assert_has(by_role(:link, name: "Harbor mornings"))
      |> refute_has(by_role(:link, name: "Harbor evenings"))
    end
  end

  describe "the entries overview" do
    # The grid is the one screen that shows every entry at once, so it
    # is where somebody looks for what is still open.
    test "marks a live entry whose words have run ahead", %{conn: conn, kb: kb} do
      article = published_post(user: kb, title: "Harbor mornings")

      conn
      |> sign_in()
      |> open("/admin/texts")
      |> refute_has(by_css(".card .cm") |> filter(has_text: "Edited since publishing"))

      {:ok, _} = Articles.update_text(article, %{title: "Harbor evenings"})

      conn
      |> open("/admin/texts")
      |> assert(contain_text(by_css(".card .cm"), "Edited since publishing"))
    end
  end

  describe "the overviews name the author" do
    test "beside the day, in the admin area and on the reader's side", %{conn: conn, kb: kb} do
      {:ok, kb} = Texttile.Accounts.update_display_name(kb, "Klaus Breyer")
      article = published_post(user: kb, title: "Harbor mornings")

      conn
      |> sign_in()
      |> open("/admin/texts")
      |> assert(contain_text(by_css(".card .cm"), "Klaus Breyer"))

      conn
      |> open_page("/blog")
      |> assert(contain_text(by_css(".card-wrap .cm"), "Klaus Breyer"))
      |> open_page(Articles.public_path(article))
      |> assert(contain_text(by_css("#by"), "Klaus Breyer"))
    end
  end
end
