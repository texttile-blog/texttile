defmodule TexttileWeb.SettingsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
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
      {:ok, view, html} = live(conn, ~p"/settings")

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
      {:ok, view, _} = live(conn, ~p"/settings")

      view
      |> form("#site-form", %{"settings" => %{"site_title" => "Two of us"}})
      |> render_change(%{"_target" => ["settings", "site_title"]})

      assert Settings.get(:site_title) == "Two of us"
    end

    test "the language select saves and an invalid max edge says no", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")

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
      {:ok, view, html} = live(conn, ~p"/settings")
      assert html =~ "confirmation link"

      html =
        view
        |> form("#comments-form", %{"settings" => %{"comments_require_confirmation" => "false"}})
        |> render_change(%{"_target" => ["settings", "comments_require_confirmation"]})

      assert Settings.get(:comments_require_confirmation) == false
      assert html =~ "Comments appear at once"
    end

    test "the about text renders as markdown in the preview", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")

      html =
        view
        |> form("#about-form", %{"settings" => %{"about_markdown" => "# Us\n\n**bold** words"}})
        |> render_change(%{"_target" => ["settings", "about_markdown"]})

      assert html =~ "<h1>Us</h1>"
      assert html =~ "<strong>bold</strong>"
    end

    test "another admin's change arrives without a reload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")

      {:ok, _} = Settings.put(:site_title, "Changed elsewhere")

      assert render(view) =~ "Changed elsewhere"
    end
  end

  describe "users" do
    test "lists everybody with you marked", %{conn: conn} do
      other = user_fixture(%{username: "julia"})
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "julia"
      assert html =~ "you"
      assert html =~ other.email
    end

    test "adding somebody creates the account and mails the invitation", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")

      html =
        view
        |> form("#add-user-form", %{
          "user" => %{"username" => "julia", "email" => "j@example.org"}
        })
        |> render_submit()

      assert html =~ "invitation went to j@example.org"
      assert html =~ "waiting for the first sign-in"
      assert Accounts.invited?(Accounts.get_user_by_email("j@example.org"))
      assert_email_sent(fn email -> assert email.subject =~ "admin account" end)
    end

    test "a taken username stays on the form and says why", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")

      html =
        view
        |> form("#add-user-form", %{"user" => %{"username" => "kb", "email" => "j2@example.org"}})
        |> render_submit()

      assert html =~ "already"
    end

    test "the reset button mails a fresh link", %{conn: conn} do
      other = user_fixture(%{username: "julia"})
      {:ok, view, _} = live(conn, ~p"/settings")

      html =
        view |> element("#user-#{other.id} button", "Send a password reset") |> render_click()

      assert html =~ "Password reset sent to #{other.email}"
      assert_email_sent(fn email -> assert email.subject =~ "password" end)
    end

    test "deleting somebody asks first, then they are gone", %{conn: conn} do
      other = user_fixture(%{username: "julia"})
      {:ok, view, _} = live(conn, ~p"/settings")

      html = view |> element("#user-#{other.id} button", "Delete") |> render_click()
      assert html =~ "Delete the account of julia?"

      view |> element("#dialog-ok") |> render_click()

      refute has_element?(view, "#user-#{other.id}")
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(other.id) end
    end

    test "your own row cannot be deleted", %{conn: conn, user: user} do
      _other = user_fixture(%{username: "julia"})
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "another admin removes it"
      assert html =~ ~r/<button[^>]*id="delete-user-#{user.id}"[^>]*disabled/
    end

    test "the lone account explains why it cannot go", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "The only account left"
      assert html =~ ~r/<button[^>]*id="delete-user-#{user.id}"[^>]*disabled/
    end

    test "an invited account offers the invitation again, not a reset", %{conn: conn} do
      {:ok, invited} =
        Accounts.create_user(%{"username" => "julia", "email" => "j@example.org"},
          site: "s",
          link_url: fn t -> "http://x/link/#{t}" end
        )

      {:ok, view, _} = live(conn, ~p"/settings")

      html =
        view
        |> element("#user-#{invited.id} button", "Send the invitation again")
        |> render_click()

      assert html =~ "Invitation sent again to j@example.org"
      assert html =~ "still waiting for the first sign-in"
    end

    test "a second click on the confirm button is a no-op, not a crash", %{conn: conn} do
      other = user_fixture(%{username: "julia"})
      {:ok, view, _} = live(conn, ~p"/settings")

      view |> element("#user-#{other.id} button", "Delete") |> render_click()
      view |> element("#dialog-ok") |> render_click()
      html = render_click(view, "delete_user", %{})

      refute html =~ "julia@"
      assert Process.alive?(view.pid)
    end
  end

  describe "logo and favicon" do
    test "an uploaded logo lands below the uploads root and in the settings", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings")
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

  describe "storage" do
    test "shows both install paths and clears the image cache", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings")

      assert html =~ Uploads.root()
      assert html =~ "Clear image cache"

      assert view |> element("button", "Clear image cache") |> render_click() =~ "cache cleared"
    end
  end
end
