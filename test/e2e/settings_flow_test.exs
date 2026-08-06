defmodule TexttileWeb.E2E.SettingsFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Settings
  alias Texttile.Uploads

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  setup do
    File.rm_rf!(Uploads.root())

    # The browser talks to the same node, so the configured usernames are
    # the ones these tests set. They go back afterwards.
    Texttile.DataCase.restore_admin_users_afterwards()

    %{kb: user_fixture(%{username: "kb"})}
  end

  describe "the settings screen" do
    test "opens from the menu and saves a title the moment it changes", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click_button("#wmBtn", "Texttile")
        |> click_link("Settings")
        |> assert_has("#crumb", text: "Settings")
        |> assert_has("#savedSettings", text: "Last saved")
        |> fill_in("Site title", with: "Two of us")
        |> assert_has("#savedSettings", text: "Last saved · just now")

      assert Settings.get(:site_title) == "Two of us"

      # the value survives a full reload
      conn
      |> visit("/desk/settings")
      |> assert_has("#setting-site_title[value='Two of us']")
    end

    test "the digit 9 jumps to Settings unless you are typing", %{conn: conn} do
      conn
      |> sign_in()
      |> press("body", "9")
      |> assert_has("#crumb", text: "Settings")
      |> press("#setting-site_title", "2")
      |> assert_has("#crumb", text: "Settings")
    end

    test "the comments toggle rewrites its explanation", %{conn: conn} do
      conn
      |> sign_in()
      |> visit("/desk/settings")
      |> assert_has("#setCmtNote", text: "one confirmation link per address")
      |> uncheck("Readers confirm their email", exact: false)
      |> assert_has("#setCmtNote", text: "nobody confirms anything")

      assert Settings.get(:comments_require_confirmation) == false
    end

    test "an uploaded logo replaces the default mark", %{conn: conn} do
      path = Path.join(System.tmp_dir!(), "e2e-logo.svg")

      File.write!(
        path,
        "<svg xmlns='http://www.w3.org/2000/svg'><rect width='4' height='4'/></svg>"
      )

      conn
      |> sign_in()
      |> visit("/desk/settings")
      |> assert_has("#name-logo", text: "Default: the Texttile mark")
      |> upload("#logo-form input[type=file]", "Upload", path, exact: false)
      |> assert_has("#name-logo", text: "e2e-logo.svg")
      |> click_button("#reset-logo", "Use default")
      |> assert_has("#name-logo", text: "Default: the Texttile mark")
    end
  end

  describe "user management" do
    test "a configured name signs in for the first time, then deletes kb", %{
      conn: conn,
      kb: kb
    } do
      # julia stands in the configuration and has no account yet
      configure_admins(["kb", "julia"])

      conn
      |> sign_in()
      |> visit("/desk/settings")
      |> assert_has("#waitingUsers", text: "julia")

      # she takes the browser, types her name and chooses a password
      conn
      |> visit("/desk/profile")
      |> click_link("#sign-out", "Sign out")
      |> assert_has("p", text: "Admin sign-in")
      |> fill_in("Username", with: "julia")
      |> click_button("Sign in")
      |> assert_has("h2", text: "Choose a password")
      |> fill_in("Password", with: "julias own password")
      |> fill_in("Repeat the password", with: "julias own password")
      |> fill_in("Email address", with: "julia@example.org")
      |> click_button("Create the account and sign in")
      |> assert_has("#crumb", text: "Texts")

      # julia is a full admin now, equal to kb. Her own row cannot go
      # (another admin removes it, not you), but she can delete kb,
      # with one confirmation in between.
      julia = Enum.find(Texttile.Accounts.list_users(), &(&1.username == "julia"))

      conn
      |> visit("/desk/settings")
      |> assert_has("#user-#{julia.id}", text: "you")
      |> assert_has("#delete-user-#{julia.id}[disabled]")
      |> click_button("#delete-user-#{kb.id}", "Delete")
      |> assert_has("h2", text: "Delete the account of kb?")
      |> click_button("#dialog-ok", "Delete the account")
      |> refute_has("#usersList", text: kb.email)
    end
  end

  defp sign_in(conn) do
    conn
    |> visit("/login")
    |> fill_in("Username", with: "kb")
    |> fill_in("Password", with: valid_password())
    |> click_button("Sign in")
    |> assert_has("#crumb", text: "Texts")
  end
end
