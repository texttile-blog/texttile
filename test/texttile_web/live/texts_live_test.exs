defmodule TexttileWeb.TextsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Texttile.Articles

  setup :register_and_log_in_user

  test "shows the desk shell with the wordmark menu", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/edit")

    assert html =~ "Texts"
    assert has_element?(view, "#topbar")
    assert has_element?(view, "#wmBtn")
    assert has_element?(view, "#crumb", "Texts")

    # the menu: the sections with their digits, profile, sign out
    assert has_element?(view, "#navMenu", "New text")
    assert has_element?(view, "#navMenu", "Comments")
    assert has_element?(view, "#navMenu", "Newsletter")
    assert has_element?(view, "#navMenu", "Stats")
    assert has_element?(view, "#navMenu", "Settings")
    assert has_element?(view, "#navMenu", "View site")
    assert has_element?(view, "#navMenu a", "Your profile")
    assert has_element?(view, "#navMenu a", "Sign out")

    # presence: alone at the desk
    assert has_element?(view, "#liveBlock", "No one else right now.")
  end

  test "names the signed-in admin in the menu", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit")
    assert has_element?(view, "#wmMe", user.username)
  end

  describe "the grid" do
    test "lists the texts as cards", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(article, %{title: "Fourteen doors", body: "wood"})

      {:ok, view, _html} = live(conn, ~p"/edit")
      assert has_element?(view, "#cards .card", "Fourteen doors")
      assert has_element?(view, "#gridCount", "1 text")
    end

    test "a card wears the oldest gallery image, live", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/edit")

      assert has_element?(view, "#cards .cimg.empty")

      path = Path.join(System.tmp_dir!(), "cover-#{System.unique_integer([:positive])}.jpg")
      {:ok, black} = Vix.Vips.Operation.black(20, 10)
      :ok = Vix.Vips.Image.write_to_file(black, path)
      {:ok, image} = Texttile.Gallery.add_image(article, path, "cover.jpg")

      refute has_element?(view, "#cards .cimg.empty")
      assert render(view) =~ "/renditions/320/#{image.path}"
    end

    test "an untitled draft reads Untitled", %{conn: conn, user: user} do
      {:ok, _} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/edit")
      assert has_element?(view, "#cards .card", "Untitled")
    end

    test "filters by status", %{conn: conn, user: user} do
      {:ok, draft} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(draft, %{title: "Draft one", body: ""})
      {:ok, live_article} = Articles.create_draft(user)
      {:ok, live_article} = Articles.update_text(live_article, %{title: "Live one", body: ""})
      {:ok, _} = Articles.publish(live_article, user)

      {:ok, view, _html} = live(conn, ~p"/edit")

      view |> element("[data-f=published]") |> render_click()
      refute has_element?(view, "#cards .card", "Draft one")
      assert has_element?(view, "#cards .card", "Live one")

      view |> element("[data-f=draft]") |> render_click()
      assert has_element?(view, "#cards .card", "Draft one")
      refute has_element?(view, "#cards .card", "Live one")
    end

    test "searches title, tags and body", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(article, %{title: "Doors", body: "wooden ones"})
      {:ok, other} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(other, %{title: "Trains", body: "slow ones"})

      {:ok, view, _html} = live(conn, ~p"/edit")
      view |> element("#grid-search") |> render_change(%{q: "wooden"})
      assert has_element?(view, "#cards .card", "Doors")
      refute has_element?(view, "#cards .card", "Trains")
    end
  end

  describe "New text" do
    test "creates a draft and opens the editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/edit")

      view |> element("#new-text") |> render_click()

      assert [article] = Articles.list_articles()
      assert article.status == "draft"
      assert_redirect(view, "/edit/texts/#{article.id}")
    end
  end
end
