defmodule TexttileWeb.E2E.SettingsFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Settings
  alias Texttile.Uploads

  @moduletag :e2e

  setup do
    File.rm_rf!(Uploads.root())

    # Mails from the server processes land in this test process.
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

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
      |> visit("/settings")
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
      |> visit("/settings")
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
      |> visit("/settings")
      |> assert_has("#name-logo", text: "Default: the Texttile mark")
      |> upload("#logo-form input[type=file]", "Upload", path, exact: false)
      |> assert_has("#name-logo", text: "e2e-logo.svg")
      |> click_button("#reset-logo", "Use default")
      |> assert_has("#name-logo", text: "Default: the Texttile mark")
    end
  end

  describe "user management" do
    test "invite, first sign-in through the mailed link, delete", %{conn: conn, kb: kb} do
      # kb invites julia and the row says what it waits for
      conn
      |> sign_in()
      |> visit("/settings")
      |> fill_in("Username", with: "julia")
      |> fill_in("Email", with: "julia@example.org")
      |> click_button("Add")
      |> assert_has("#newUserState", text: "invitation went to julia@example.org")
      |> assert_has("#usersList", text: "waiting for the first sign-in")

      # the mail carries the link; julia opens it and picks a password
      assert_receive {:email, %Swoosh.Email{to: [{_, "julia@example.org"}]} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> assert_has("#link-who", text: "belongs to the account julia")
      |> fill_in("New password", with: "julias own password")
      |> click_button("Set the password and sign in")
      |> assert_has("#crumb", text: "Texts")

      # julia is a full admin now, equal to kb. Her own row cannot go
      # (another admin removes it, not you), but she can delete kb,
      # with one confirmation in between.
      julia = Texttile.Accounts.get_user_by_email("julia@example.org")

      conn
      |> visit("/settings")
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
