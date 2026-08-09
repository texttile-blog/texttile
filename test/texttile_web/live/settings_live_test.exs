defmodule TexttileWeb.SettingsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  alias Texttile.Accounts
  alias Texttile.Articles
  alias Texttile.Settings
  alias Texttile.Uploads

  setup %{conn: conn} do
    user = user_fixture(%{username: "kb"})
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "the screen" do
    test "shows every section with the saved values", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Settings"
      assert html =~ "Last saved"

      for section <- ~w(Site About Theme Comments Tags Users Images Storage) do
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

    test "a new password says who will get it by mail", %{conn: conn} do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Texttile.Newsletter.add("one@example.org")

      {:ok, view, _} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#access-form", %{"settings" => %{"site_password" => "another word"}})
        |> render_change(%{"_target" => ["settings", "site_password"]})

      assert html =~ "mails the new word to 1 subscriber"
    end

    test "a front page that is no longer published shows as the list again", %{conn: conn} do
      user = Texttile.AccountsFixtures.user_fixture()
      page = Texttile.ArticlesFixtures.published_page(title: "Welcome", user: user)
      {:ok, _} = Settings.put(:front_page, "page:#{page.id}")
      {:ok, _} = Articles.unpublish(page, user)

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

    test "the language select saves, and the screen comes back speaking it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      # The whole page is asked for again, not a live step: the shell
      # around this view carries the language too, and only a fresh
      # request draws the shell.
      assert {:error, {:redirect, %{to: "/admin/settings"}}} =
               view
               |> form("#site-form", %{"settings" => %{"language" => "de"}})
               |> render_change(%{"_target" => ["settings", "language"]})

      assert Settings.get(:language) == "de"

      {:ok, _view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Einstellungen"
      # the shell, which a live step would have left in English
      assert html =~ ~s(<html lang="de")
      assert html =~ "Erneut versuchen"
    end

    test "an invalid max edge says no", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#images-form", %{"settings" => %{"image_max_edge" => "100"}})
        |> render_change(%{"_target" => ["settings", "image_max_edge"]})

      assert html =~ "at least 800"
      assert Settings.get(:image_max_edge) == 2560
    end

    test "the video edge saves, and a number nobody can use says no", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      view
      |> form("#videos-form", %{"settings" => %{"video_max_edge" => "1920"}})
      |> render_change(%{"_target" => ["settings", "video_max_edge"]})

      assert Settings.get(:video_max_edge) == 1920

      html =
        view
        |> form("#videos-form", %{"settings" => %{"video_max_edge" => "100"}})
        |> render_change(%{"_target" => ["settings", "video_max_edge"]})

      assert html =~ "at least 480"
      assert Settings.get(:video_max_edge) == 1920
    end

    test "the page size is a row of sizes, and picking one saves it", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Pagination"

      for size <- [10, 25, 50, 100, 150, 200] do
        assert has_element?(view, ~s(#setting-posts_per_page option[value="#{size}"]))
      end

      view
      |> form("#front-page-form", %{"settings" => %{"posts_per_page" => "50"}})
      |> render_change(%{"_target" => ["settings", "posts_per_page"]})

      assert Settings.get(:posts_per_page) == 50
    end

    test "a size from somewhere else keeps its place in the row", %{conn: conn} do
      {:ok, _} = Settings.put(:posts_per_page, 4)
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      assert has_element?(view, ~s(#setting-posts_per_page option[value="4"][selected]))
      assert has_element?(view, ~s(#setting-posts_per_page option[value="10"]))
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

    test "the mail-me-every-comment switch saves and explains itself", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Mail me every new comment"

      html =
        view
        |> form("#comments-form", %{"settings" => %{"notify_on_comment" => "false"}})
        |> render_change(%{"_target" => ["settings", "notify_on_comment"]})

      assert Settings.get(:notify_on_comment) == false
      assert html =~ "No mail goes out for a comment"
    end

    test "the about text renders as markdown in the preview", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      # About is the entry editor with the pictures taken out, so its
      # changes arrive from the hook and not through a form
      html = render_hook(view, "about_changed", %{"text" => "# Us\n\n**bold** words"})

      assert html =~ "<h1>Us</h1>"
      assert html =~ "<strong>bold</strong>"
      assert Settings.get(:about_markdown) == "# Us\n\n**bold** words"
    end

    test "another admin's change arrives without a reload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      {:ok, _} = Settings.put(:site_title, "Changed elsewhere")

      assert render(view) =~ "Changed elsewhere"
    end
  end

  describe "tags" do
    setup %{user: user} do
      {:ok, one} = Articles.create_draft(user)
      {:ok, two} = Articles.create_draft(user)
      {:ok, one} = Articles.update_settings(one, %{tags: "sea, fog"})
      {:ok, two} = Articles.update_settings(two, %{tags: "sea"})
      %{one: one, two: two}
    end

    test "lists every tag with the number of texts on it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(view, "#tagrow-sea", "sea")
      assert has_element?(view, "#tagrow-sea", "2 entries")
      assert has_element?(view, "#tagrow-fog", "1 entry")
    end

    test "deleting a tag asks first, then takes it off every text",
         %{conn: conn, one: one, two: two} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      view |> element("#delete-tag-sea") |> render_click()
      assert has_element?(view, "#dialog-ok")

      view |> element("#dialog-ok") |> render_click()

      assert Articles.get_article!(one.id).tags == "fog"
      assert Articles.get_article!(two.id).tags == ""
      refute has_element?(view, "#tagrow-sea")
      assert has_element?(view, "#tagrow-fog")
      assert has_element?(view, "#savedSettings")
    end

    test "the way out of the question leaves every tag where it is",
         %{conn: conn, one: one} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

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

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(view, "#tagsList", "No entry carries a tag yet")
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

    test "a name in the configuration without an account is not listed", %{conn: conn} do
      configure_admins(["kb", "julia"])
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      # The screen lists accounts, not names that could become one:
      # nobody can act on a name that has never signed in.
      refute html =~ "Not here yet"
      refute html =~ "These names may sign in but have no account yet"
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

      assert html =~ "This one is you"
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

    test "Reset puts the iris default back", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      # nothing to reset while the site wears the default
      refute has_element?(view, "#reset-theme")

      {:ok, _} = Settings.put(:theme_css, ":root { --tt-accent: hotpink; }")
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      html = view |> element("#reset-theme") |> render_click()

      assert Settings.get(:theme_css) == ""
      refute html =~ "hotpink"
      assert html =~ "--tt-accent"
      refute has_element?(view, "#reset-theme")
    end
  end

  describe "storage" do
    test "shows both install paths and clears the image cache", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      assert html =~ Uploads.root()
      assert html =~ "Clear image cache"

      assert view |> element("button", "Clear image cache") |> render_click() =~ "cache cleared"
    end

    test "names every folder, counts what is in it, and says what is left", %{conn: conn} do
      {:ok, _} = Uploads.put_body_image(Texttile.ArticlesFixtures.jpg_fixture(), "pier.jpg")

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      for dir <- ~w(images videos site cache) do
        assert has_element?(view, "#usage-#{dir}", "#{dir}/")
      end

      assert has_element?(view, "#usage-images", "1")
      assert has_element?(view, "#usage-db")
      assert has_element?(view, "#usage-total")
      # df answers on every machine this runs on
      assert has_element?(view, "#usage-free")
    end

    # Reading the report walks every folder of the volume and forks df.
    # Settings.put broadcasts to every subscriber, this tab included,
    # so without a test on the key it ran again on every debounce of
    # every field on the screen. A slightly stale count is the trade,
    # and the one setting that moves files still refreshes it.
    test "the volume report is not walked again on every field that saves", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      images = fn -> view |> element("#usage-images") |> render() end
      assert images.() =~ ~s(<td class="n num">0</td>)

      {:ok, _} = Uploads.put_body_image(Texttile.ArticlesFixtures.jpg_fixture(), "pier.jpg")

      view
      |> form("#site-form", %{"settings" => %{"site_title" => "Two of us"}})
      |> render_change(%{"_target" => ["settings", "site_title"]})

      assert images.() =~ ~s(<td class="n num">0</td>)

      view
      |> form("#images-form", %{"settings" => %{"image_max_edge" => "2000"}})
      |> render_change(%{"_target" => ["settings", "image_max_edge"]})

      assert images.() =~ ~s(<td class="n num">1</td>)
    end

    test "the biggest upload is a setting, and it has a floor and a ceiling", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Biggest upload"
      assert has_element?(view, "#setting-max_upload_mb[value='512']")

      view
      |> form("#upload-form", %{"settings" => %{"max_upload_mb" => "256"}})
      |> render_change(%{"_target" => ["settings", "max_upload_mb"]})

      assert Settings.get(:max_upload_mb) == 256

      html =
        view
        |> form("#upload-form", %{"settings" => %{"max_upload_mb" => "4000"}})
        |> render_change(%{"_target" => ["settings", "max_upload_mb"]})

      assert html =~ "at most 2048 MB"
      assert Settings.get(:max_upload_mb) == 256
    end
  end
end
