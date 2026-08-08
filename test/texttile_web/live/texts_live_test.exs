defmodule TexttileWeb.TextsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  setup :register_and_log_in_user

  test "shows the admin shell with the wordmark menu", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/texts")

    assert html =~ "Entries"
    assert has_element?(view, "#topbar")
    assert has_element?(view, "#wmBtn")
    assert has_element?(view, "#crumb", "Entries")

    # the menu: the sections with their digits, profile, sign out
    assert has_element?(view, "#navMenu", "New entry")
    assert has_element?(view, "#navMenu", "Comments")
    assert has_element?(view, "#navMenu", "Newsletter")
    assert has_element?(view, "#navMenu", "Stats")
    assert has_element?(view, "#navMenu", "Settings")
    # the site opens beside the admin area, not over it
    assert has_element?(view, ~s(#navMenu a[href="/"][target="_blank"]), "View site")
    assert has_element?(view, "#navMenu a", "Your profile")
    assert has_element?(view, "#navMenu a", "Sign out")

    # presence: alone in the admin area
    assert has_element?(view, "#liveBlock", "No one else right now.")
  end

  test "names the signed-in admin in the menu", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/texts")
    assert has_element?(view, "#wmMe", user.username)
  end

  describe "the grid" do
    test "lists the entries as cards", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(article, %{title: "Fourteen doors", body: "wood"})

      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      assert has_element?(view, "#cards .card", "Fourteen doors")
      assert has_element?(view, "#gridCount", "1 entry")
    end

    test "a card wears the oldest gallery image, live", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/admin/texts")

      assert has_element?(view, "#cards .cimg.empty")

      path = Path.join(System.tmp_dir!(), "cover-#{System.unique_integer([:positive])}.jpg")
      {:ok, black} = Vix.Vips.Operation.black(20, 10)
      :ok = Vix.Vips.Image.write_to_file(black, path)
      {:ok, image} = Texttile.Gallery.add_file(article, path, "cover.jpg")

      refute has_element?(view, "#cards .cimg.empty")
      assert render(view) =~ "/renditions/320/#{image.path}"
    end

    test "a card counts the comments under its text, live", %{conn: conn, user: user} do
      article = Texttile.ArticlesFixtures.published_post(title: "The harbour", user: user)

      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      refute has_element?(view, "#cards .card .cm", "comment")

      {:ok, _} =
        Texttile.Comments.post(
          article,
          %{"name" => "A reader", "email" => "one@example.org", "body" => "First words"},
          confirm_url: &"http://example.org/comments/confirm/#{&1}"
        )

      assert has_element?(view, "#cards .card .cm", "1 comment")

      {:ok, _} =
        Texttile.Comments.post(
          article,
          %{"name" => "Another", "email" => "two@example.org", "body" => "Later words"},
          confirm_url: &"http://example.org/comments/confirm/#{&1}"
        )

      assert has_element?(view, "#cards .card .cm", "2 comments")
    end

    test "a draft that once was live keeps its comment count", %{conn: conn, user: user} do
      article = Texttile.ArticlesFixtures.published_post(title: "The harbour", user: user)

      {:ok, _} =
        Texttile.Comments.post(
          article,
          %{"name" => "A reader", "email" => "one@example.org", "body" => "First words"},
          confirm_url: &"http://example.org/comments/confirm/#{&1}"
        )

      {:ok, _} = Articles.unpublish(article, user)

      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      assert has_element?(view, "#cards .card .cm", "1 comment")
    end

    test "an untitled draft reads Untitled", %{conn: conn, user: user} do
      {:ok, _} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      assert has_element?(view, "#cards .card", "Untitled")
    end

    test "filters by status", %{conn: conn, user: user} do
      {:ok, draft} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(draft, %{title: "Draft one", body: ""})
      {:ok, live_article} = Articles.create_draft(user)
      {:ok, live_article} = Articles.update_text(live_article, %{title: "Live one", body: ""})
      {:ok, _} = Articles.publish(live_article, user)

      {:ok, view, _html} = live(conn, ~p"/admin/texts")

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

      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      view |> element("#grid-search") |> render_change(%{q: "wooden"})
      assert has_element?(view, "#cards .card", "Doors")
      refute has_element?(view, "#cards .card", "Trains")
    end
  end

  describe "the archive" do
    setup %{user: user} do
      %{
        august:
          published_post(title: "Harbour mornings", publish_date: ~D[2026-08-08], user: user),
        march: published_post(title: "Desert nights", publish_date: ~D[2026-03-02], user: user),
        older: published_post(title: "The long winter", publish_date: ~D[2024-12-24], user: user)
      }
    end

    test "narrows the grid to one year, then to one month", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/texts")

      assert has_element?(view, "#years .per", "2026")
      assert has_element?(view, "#years .per", "2024")
      refute has_element?(view, "#months")

      view |> element("#years button.per", "2026") |> render_click()
      assert has_element?(view, "#cards .card", "Harbour mornings")
      assert has_element?(view, "#cards .card", "Desert nights")
      refute has_element?(view, "#cards .card", "The long winter")

      # only the months that carry entries
      assert has_element?(view, "#months .per", "Aug")
      assert has_element?(view, "#months .per", "Mar")
      refute has_element?(view, "#months .per", "May")

      view |> element("#months button.per", "Aug") |> render_click()
      assert has_element?(view, "#cards .card", "Harbour mornings")
      refute has_element?(view, "#cards .card", "Desert nights")
    end

    test "All years counts what the search found, like the years beside it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      assert has_element?(view, "#years .per.on", "All years")

      view |> element("#grid-search") |> render_change(%{q: "harbour"})

      # one entry carries the word, and it is the only one under 2026
      assert has_element?(view, "#years .per", "All years1")
      refute has_element?(view, "#years .per", "All years3")
    end

    test "lets go of a year the search has emptied", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/texts")

      view |> element("#years button.per", "2024") |> render_click()
      assert has_element?(view, "#cards .card", "The long winter")

      view |> element("#grid-search") |> render_change(%{q: "harbour"})
      assert has_element?(view, "#cards .card", "Harbour mornings")
      refute has_element?(view, "#years .per.on", "2024")
    end

    test "drops the month when another year is chosen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/texts")

      view |> element("#years button.per", "2026") |> render_click()
      view |> element("#months button.per", "Aug") |> render_click()
      assert has_element?(view, "#months .per.on", "Aug")

      view |> element("#years button.per", "2024") |> render_click()
      assert has_element?(view, "#cards .card", "The long winter")
      refute has_element?(view, "#months .per.on", "Aug")
    end

    test "a draft without a day stands under All years and nowhere else", %{
      conn: conn,
      user: user
    } do
      {:ok, draft} = Articles.create_draft(user)
      {:ok, _} = Articles.update_text(draft, %{title: "No day yet", body: ""})

      {:ok, view, _html} = live(conn, ~p"/admin/texts")
      assert has_element?(view, "#cards .card", "No day yet")

      view |> element("#years button.per", "2026") |> render_click()
      refute has_element?(view, "#cards .card", "No day yet")
    end
  end

  describe "New entry" do
    test "creates a draft and opens the editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/texts")

      view |> element("#new-text") |> render_click()

      assert [article] = Articles.list_articles()
      assert article.status == "draft"
      assert_redirect(view, "/admin/texts/#{article.id}")
    end
  end
end
