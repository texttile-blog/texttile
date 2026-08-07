defmodule TexttileWeb.SettingsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  alias Texttile.Accounts
  alias Texttile.Settings
  alias Texttile.Uploads

  setup %{conn: conn} do
    File.rm_rf!(Uploads.root())
    user = user_fixture(%{username: "kb"})
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "the screen" do
    test "shows every section with the saved values", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Settings"
      assert html =~ "Last saved"

      for section <- ~w(Site About Theme Comments Users Images Storage) do
        assert has_element?(view, "h2", section)
      end

      assert has_element?(view, "#setting-site_title")
    end
  end

  describe "instant save" do
    test "a changed title is stored the moment it changes", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      view
      |> form("#site-form", %{"settings" => %{"site_title" => "Two of us"}})
      |> render_change(%{"_target" => ["settings", "site_title"]})

      assert Settings.get(:site_title) == "Two of us"
    end

    test "the blog password field is on screen for a public blog too", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/settings")
      assert html =~ ~s(id="setting-site_password")
    end

    test "protecting the blog without a password says what is missing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#access-form", %{"settings" => %{"site_visibility" => "protected"}})
        |> render_change(%{"_target" => ["settings", "site_visibility"]})

      assert html =~ "Protected once the blog password below is set"

      view
      |> form("#access-form", %{"settings" => %{"site_password" => "sesame"}})
      |> render_change(%{"_target" => ["settings", "site_password"]})

      html =
        view
        |> form("#access-form", %{"settings" => %{"site_visibility" => "protected"}})
        |> render_change(%{"_target" => ["settings", "site_visibility"]})

      assert html =~ "The blog waits behind the password now"
    end

    test "a front page that is no longer published shows as the list again", %{conn: conn} do
      user = Texttile.AccountsFixtures.user_fixture()
      page = Texttile.ArticlesFixtures.published_page(title: "Welcome", user: user)
      {:ok, _} = Settings.put(:front_page, "page:#{page.id}")
      {:ok, _} = Texttile.Articles.unpublish(page, user)

      {:ok, _view, html} = live(conn, ~p"/admin/settings")
      refute html =~ ~s(id="front-page-choice")
    end

    test "a published page unlocks the fixed front page and saves it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")
      assert has_element?(view, "#front-page-form input[type=radio][disabled]")

      page = Texttile.ArticlesFixtures.published_page(title: "Welcome")

      {:ok, view, _} = live(conn, ~p"/admin/settings")
      refute has_element?(view, "#front-page-form input[type=radio][disabled]")

      view
      |> form("#front-page-form", %{"settings" => %{"front_page" => "page:#{page.id}"}})
      |> render_change(%{"_target" => ["settings", "front_page"]})

      assert Settings.get(:front_page) == "page:#{page.id}"
      assert has_element?(view, "#front-page-choice")
    end

    test "the language select saves and an invalid max edge says no", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      view
      |> form("#site-form", %{"settings" => %{"language" => "de"}})
      |> render_change(%{"_target" => ["settings", "language"]})

      assert Settings.get(:language) == "de"

      html =
        view
        |> form("#images-form", %{"settings" => %{"image_max_edge" => "100"}})
        |> render_change(%{"_target" => ["settings", "image_max_edge"]})

      assert html =~ "at least 800"
      assert Settings.get(:image_max_edge) == 2560
    end

    test "the comments toggle rewrites its own explanation", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "confirmation link"

      html =
        view
        |> form("#comments-form", %{"settings" => %{"comments_require_confirmation" => "false"}})
        |> render_change(%{"_target" => ["settings", "comments_require_confirmation"]})

      assert Settings.get(:comments_require_confirmation) == false
      assert html =~ "Comments appear at once"
    end

    test "the about text renders as markdown in the preview", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#about-form", %{"settings" => %{"about_markdown" => "# Us\n\n**bold** words"}})
        |> render_change(%{"_target" => ["settings", "about_markdown"]})

      assert html =~ "<h1>Us</h1>"
      assert html =~ "<strong>bold</strong>"
    end

    test "another admin's change arrives without a reload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      {:ok, _} = Settings.put(:site_title, "Changed elsewhere")

      assert render(view) =~ "Changed elsewhere"
    end
  end

  describe "users" do
    test "lists everybody with you marked", %{conn: conn} do
      other = user_fixture(%{username: "julia"})
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "julia"
      assert html =~ "you"
      assert html =~ other.email
    end

    test "names in the configuration without an account are waiting", %{conn: conn} do
      configure_admins(["kb", "julia"])
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Not here yet"
      assert html =~ "julia"
      assert html =~ "These names may sign in but have no account yet"
    end

    test "with every configured name in use, nobody is waiting", %{conn: conn, user: user} do
      configure_admins([user.username])
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Every name in ADMIN_USERS has an account"
    end

    # An account whose name left the configuration is still a row here,
    # and it has to say why that person no longer gets in.
    test "an account that left the configuration says so", %{conn: conn, user: user} do
      other = user_fixture(%{username: "julia"})
      configure_admins([user.username])

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "not in ADMIN_USERS"
      assert html =~ "cannot sign in"
      assert html =~ "user-#{other.id}"
    end

    test "the screen offers no way to add somebody", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      refute html =~ "add-user-form"
      refute has_element?(view, "#add-user-form")
    end

    test "deleting somebody asks first, then they are gone", %{conn: conn} do
      other = user_fixture(%{username: "julia"})
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      html = view |> element("#user-#{other.id} button", "Delete") |> render_click()
      assert html =~ "Delete the account of julia?"

      view |> element("#dialog-ok") |> render_click()

      refute has_element?(view, "#user-#{other.id}")
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(other.id) end
    end

    test "your own row cannot be deleted", %{conn: conn, user: user} do
      _other = user_fixture(%{username: "julia"})
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "another admin removes it"
      assert html =~ ~r/<button[^>]*id="delete-user-#{user.id}"[^>]*disabled/
    end

    test "the lone account explains why it cannot go", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "The only account left"
      assert html =~ ~r/<button[^>]*id="delete-user-#{user.id}"[^>]*disabled/
    end
  end

  describe "logo and favicon" do
    test "an uploaded logo lands below the uploads root and in the settings", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Default: the Texttile mark"

      view
      |> file_input("#logo-form", :logo, [
        %{
          name: "mark.svg",
          content: "<svg xmlns='http://www.w3.org/2000/svg'/>",
          type: "image/svg+xml"
        }
      ])
      |> render_upload("mark.svg")

      assert Settings.get(:logo) =~ ~r"^site/logo-"
      assert Settings.get(:logo_name) == "mark.svg"
      assert render(view) =~ "mark.svg"

      html = view |> element("#reset-logo") |> render_click()
      assert Settings.get(:logo) == nil
      assert html =~ "Default: the Texttile mark"
    end
  end

  describe "the site brand" do
    test "the bar and the page title carry the site name", %{conn: conn} do
      {:ok, _} = Settings.put(:site_title, "Two of us")

      conn = get(conn, ~p"/admin/settings")
      html = html_response(conn, 200)

      assert html =~ "Settings · Two of us"
      assert html =~ ~r/<button[^>]*id="wmBtn"[^>]*>.*Two of us/s
    end

    test "an uploaded logo replaces the mark in the bar", %{conn: conn} do
      {:ok, _} = Settings.put(:logo, "site/logo-feed.svg")

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ ~r/<button[^>]*id="wmBtn"[^>]*>.*<img[^>]*logo-feed\.svg/s
    end
  end

  describe "the theme" do
    test "the textarea starts from the iris default while nothing is stored", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "--tt-accent"
    end

    test "a stored theme is what the textarea shows", %{conn: conn} do
      {:ok, _} = Settings.put(:theme_css, ":root { --tt-accent: hotpink; }")

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "hotpink"
    end
  end

  describe "storage" do
    test "shows both install paths and clears the image cache", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      assert html =~ Uploads.root()
      assert html =~ "Clear image cache"

      assert view |> element("button", "Clear image cache") |> render_click() =~ "cache cleared"
    end
  end
end
