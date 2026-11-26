defmodule TexttileWeb.E2E.SettingsFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Settings

  describe "the settings screen" do
    test "opens from the menu and saves a title the moment it changes", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click(by_css("#wmBtn"))
        # the menu opens in the browser: wait for it, or the next click
        # races the script on a slow machine
        |> assert(contain_text(by_css("#navMenu"), "Settings"))
        |> click(by_css("#navMenu a") |> filter(has_text: "Settings"))
        |> assert(contain_text(by_css("#crumb"), "Settings"))
        |> assert(contain_text(by_css("#savedSettings"), "Saved"))
        |> fill(by_label("Site title"), "Two of us")
        # the toast is the save answering
        |> assert(contain_text(by_css("#toast"), "Saved"))

      assert Settings.get(:site_title) == "Two of us"

      # the value survives a full reload
      conn
      |> open("/admin/settings")
      |> assert_has(by_css("#setting-site_title[value='Two of us']"))
    end

    test "the digit 9 jumps to Settings unless you are typing", %{conn: conn} do
      conn
      |> sign_in()
      |> press(by_css("body"), "9")
      |> assert(contain_text(by_css("#crumb"), "Settings"))
      |> press(by_css("#setting-site_title"), "2")
      |> assert(contain_text(by_css("#crumb"), "Settings"))
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
      |> assert(contain_text(by_css("#name-logo"), "Default: the Texttile mark"))
      |> set_input_files(by_css("#logo-form input[type=file]"), path)
      |> assert(contain_text(by_css("#name-logo"), "e2e-logo.svg"))
      |> click(by_css("#reset-logo"))
      |> assert(contain_text(by_css("#name-logo"), "Default: the Texttile mark"))
    end
  end

  describe "user management" do
    test "kb invites an address, who sets a password and deletes kb", %{
      conn: conn,
      kb: kb
    } do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> refute_has(by_css("#usersList") |> filter(has_text: "julia@example.org"))
      |> fill(by_css("#invite-email"), "julia@example.org")
      |> click(by_css("#invite-send"))
      |> assert(contain_text(by_css("#inviteState"), "on its way to julia@example.org"))
      |> assert(contain_text(by_css("#usersList"), "waiting for its first password"))

      # the link is the one that went out, not one the test made up
      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      # until she opens it, her address answers like a wrong password
      conn
      |> open("/admin/profile")
      |> click(by_css("#sign-out"))
      |> assert_has(by_text("Admin sign-in"))
      |> fill(by_label("Email address"), "julia@example.org")
      |> fill(by_label("Password"), "not her password")
      |> click(by_role(:button, name: "Sign in"))
      |> assert(contain_text(by_css("#login-error"), "do not match"))

      # she opens the link and chooses a password
      conn
      |> visit(link)
      |> assert(contain_text(by_css("#link-who"), "opens the admin account of"))
      |> fill(by_label("Your password"), "julias own password")
      |> fill(by_label("Repeat the password"), "julias own password")
      |> fill(by_label("Display name"), "Julia")
      |> click(by_role(:button, name: "Open the account and sign in"))
      |> assert(contain_text(by_css("#crumb"), "Entries"))

      # julia is a full admin now, equal to kb. Her own row cannot go
      # (another admin removes it, not you), but she can delete kb,
      # with one confirmation in between.
      julia = Texttile.Accounts.get_user_by_email("julia@example.org")

      conn
      |> open("/admin/settings")
      |> assert(contain_text(by_css("#user-#{julia.id}"), "you"))
      |> refute_has(by_css("#delete-user-#{julia.id}"))
      |> click(by_css("#delete-user-#{kb.id}"))
      |> assert_has(by_role(:heading, name: "Delete the account of kb?"))
      |> click(by_css("#dialog-ok"))
      |> refute_has(by_css("#usersList") |> filter(has_text: kb.email))
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
      |> assert_has(by_css("#import-doc"))
      |> assert_script(@arrow_box, &assert(&1 <= 16))
    end

    # Access is one question with two answers, and the password belongs
    # to the second answer: it shows once that answer is picked. The rules between the rows made it three
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
      |> refute_has(by_css("#pwRow"))
      |> click(by_css("#access-form input[value=protected]"))
      |> assert_has(by_css("#pwRow"))
      |> assert_script(@access_shape, fn [ruled, off] ->
        assert ruled == 0
        assert abs(off) < 1.5
      end)
    end

    # The one thing on this screen that says which build runs. It is
    # here and nowhere a reader can reach it. The number comes from
    # mix.exs, not from Texttile.version/0: a broken reader would give
    # both sides of the assertion the same empty string.
    test "the last section names the version that runs", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> assert(text(by_css("#appVersion"), Mix.Project.config()[:version]))
    end

    # Version is too short to reach the line under the bars, so the
    # end of the page names it
    @tag Playwright.Test.use(viewport: %{width: 1440, height: 900})
    test "the end of the page marks the last section", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> run_script("() => window.scrollTo(0, document.documentElement.scrollHeight)")
      |> assert(attribute(by_css("#setNav a[aria-current]"), "href", ~r/#set-version$/))
    end
  end
end
