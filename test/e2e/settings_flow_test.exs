defmodule TexttileWeb.E2E.SettingsFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Settings

  describe "the settings screen" do
    test "opens from the menu and saves a title the moment it changes", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click_button("#wmBtn", "Texttile")
        # the menu opens in the browser: wait for it, or the next click
        # races the script on a slow machine
        |> assert_has("#navMenu", text: "Settings")
        |> click_link("Settings")
        |> assert_has("#crumb", text: "Settings")
        |> assert_has("#savedSettings", text: "Last saved")
        |> fill_in("Site title", with: "Two of us")
        |> assert_has("#savedSettings", text: "Last saved · just now")

      assert Settings.get(:site_title) == "Two of us"

      # the value survives a full reload
      conn
      |> open("/admin/settings")
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
      |> open("/admin/settings")
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
      |> open("/admin/settings")
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
      # julia stands in the configuration and has no account yet, so
      # the screen that lists accounts does not know her
      configure_admins(["kb", "julia"])

      conn
      |> sign_in()
      |> open("/admin/settings")
      |> refute_has("#usersList", text: "julia")

      # she takes the browser, types her name and chooses a password
      conn
      |> open("/admin/profile")
      |> click_link("#sign-out", "Sign out")
      |> assert_has("p", text: "Admin sign-in")
      |> fill_in("Username", with: "julia")
      |> click_button("Sign in")
      |> assert_has("h2", text: "Choose a password")
      |> fill_in("Password", with: "julias own password")
      |> fill_in("Repeat the password", with: "julias own password")
      |> fill_in("Email address", with: "julia@example.org")
      |> click_button("Create the account and sign in")
      |> assert_has("#crumb", text: "Entries")

      # julia is a full admin now, equal to kb. Her own row cannot go
      # (another admin removes it, not you), but she can delete kb,
      # with one confirmation in between.
      julia = Enum.find(Texttile.Accounts.list_users(), &(&1.username == "julia"))

      conn
      |> open("/admin/settings")
      |> assert_has("#user-#{julia.id}", text: "you")
      |> assert_has("#delete-user-#{julia.id}[disabled]")
      |> click_button("#delete-user-#{kb.id}", "Delete")
      |> assert_has("h2", text: "Delete the account of kb?")
      |> click_button("#dialog-ok", "Delete the account")
      |> refute_has("#usersList", text: kb.email)
    end
  end

  describe "the look of the settings screen" do
    # The arrow that marks a link to another tab took its size from
    # `.out`, and the IMPORT.md link is a `.link`. An SVG with no size
    # of its own fills the box it lands in, so the arrow stood as tall
    # as the paragraph.
    @arrow_box """
    () => {
      const r = document.querySelector("#import-doc svg").getBoundingClientRect()
      return Math.max(r.width, r.height)
    }
    """

    test "the arrow after IMPORT.md is the size of the words it follows", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> assert_has("#import-doc")
      |> evaluate(@arrow_box, [is_function: true], &assert(&1 <= 16))
    end

    # Access is one question with two answers, and the password belongs
    # to the second answer. The rules between the rows made it three
    # unrelated things, and the field began at the left edge, under the
    # radio instead of under the word.
    @access_shape """
    () => {
      const form = document.querySelector("#access-form")
      const ruled = [...form.querySelectorAll("label")]
        .filter(l => getComputedStyle(l).borderBottomWidth !== "0px").length
      const word = form.querySelector("label:nth-of-type(2) span span")
      const field = document.querySelector("#setting-site_password")
      return [ruled, field.getBoundingClientRect().left -
                     word.getBoundingClientRect().left]
    }
    """

    test "the blog password stands under the choice it belongs to", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> assert_has("#pwRow")
      |> evaluate(@access_shape, [is_function: true], fn [ruled, off] ->
        assert ruled == 0
        assert abs(off) < 1.5
      end)
    end

    # The one thing on this screen that says which build runs. It is
    # here and nowhere a reader can reach it.
    test "the last section names the version that runs", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> assert_has("#appVersion", text: Texttile.version())
    end
  end
end
