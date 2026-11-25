defmodule TexttileWeb.E2E.LoginFlowTest do
  use TexttileWeb.E2E

  describe "the first admin" do
    # A blog nobody has signed in to yet: these tests make their own
    # first admin, so the shared one would be in the way.
    @describetag :nobody_signed_up

    test "the address in ADMIN_USERS gets a link and walks into the admin area", %{conn: conn} do
      configure_admin_emails(["kb@example.org"])

      # what the start of the server does, without restarting it
      Texttile.Accounts.Bootstrap.run()

      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> assert(contain_text(by_css("#link-who"), "opens the admin account of"))
      |> assert(contain_text(by_css("#link-who"), "kb@example.org"))
      |> fill(by_label("Your password"), "a long password")
      |> fill(by_label("Repeat the password"), "a long password")
      |> fill(by_label("Display name"), "KB")
      |> click(by_role(:button, name: "Open the account and sign in"))
      |> assert(contain_text(by_css("#crumb"), "Entries"))
      |> assert(contain_text(by_css("h1"), "Entries"))
      |> click(by_css("#wmBtn"))
      |> assert(contain_text(by_css("#wmMe"), "KB"))
    end

    # Nobody knows this password yet, and the name under the entries is
    # chosen here or nowhere.
    test "a typo and a missing name stay on the screen", %{conn: conn} do
      configure_admin_emails(["kb@example.org"])
      Texttile.Accounts.Bootstrap.run()

      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> fill(by_label("Your password"), "a long password")
      |> fill(by_label("Repeat the password"), "a long passwort")
      |> fill(by_label("Display name"), "KB")
      |> click(by_role(:button, name: "Open the account and sign in"))
      |> assert_has(by_text("does not match the password"))
      # the name that was typed is still there after a refused answer
      |> assert_has(by_css("#link-display-name[value='KB']"))
      |> fill(by_label("Your password"), "a long password")
      |> fill(by_label("Repeat the password"), "a long password")
      |> fill(by_label("Display name"), "")
      |> click(by_role(:button, name: "Open the account and sign in"))
      |> assert_has(by_text("cannot be empty"))
      |> fill(by_label("Your password"), "a long password")
      |> fill(by_label("Repeat the password"), "a long password")
      |> fill(by_label("Display name"), "KB")
      |> click(by_role(:button, name: "Open the account and sign in"))
      |> assert(contain_text(by_css("#crumb"), "Entries"))
    end

    # There is no door on this screen that makes an account, so a
    # stranger who knows the address gets nowhere with it.
    test "the sign-in screen opens nothing for an address that was only invited", %{conn: conn} do
      configure_admin_emails(["kb@example.org"])
      Texttile.Accounts.Bootstrap.run()

      conn
      |> visit("/login")
      |> assert(contain_text(by_css("#login-nobody"), "No account here has a password yet"))
      |> fill(by_label("Email address"), "kb@example.org")
      |> fill(by_label("Password"), "let me in please")
      |> click(by_role(:button, name: "Sign in"))
      |> assert(contain_text(by_css("#login-error"), "do not match"))
    end
  end

  describe "a forgotten password" do
    test "the link from the mail sets a new one and signs in", %{conn: conn, kb: user} do
      conn
      |> visit("/login")
      |> click(by_role(:link, name: "Forgot your password?"))
      |> fill(by_label("Email address"), user.email)
      |> click(by_role(:button, name: "Send the link"))
      |> assert(contain_text(by_css("#forgot-sent"), "The mail is on its way"))

      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> assert(contain_text(by_css("#link-who"), "belongs to the account kb@example.org"))
      |> fill(by_label("New password"), "a brand new password")
      |> click(by_role(:button, name: "Set the password and sign in"))
      |> assert(contain_text(by_css("#crumb"), "Entries"))

      assert {:ok, _} =
               Texttile.Accounts.authenticate_user("kb@example.org", "a brand new password")
    end

    test "an address without an account gets no mail", %{conn: conn} do
      conn
      |> visit("/forgot")
      |> fill(by_label("Email address"), "nobody@example.org")
      |> click(by_role(:button, name: "Send the link"))
      |> assert(contain_text(by_css("#forgot-sent"), "The mail is on its way"))

      refute_receive {:email, _}, 500
    end
  end

  describe "sign-in" do
    test "wrong credentials leave a quiet line, right ones open the admin area", %{conn: conn} do
      conn
      |> visit("/admin")
      |> assert_has(by_text("Admin sign-in"))
      |> fill(by_label("Email address"), "kb@example.org")
      |> fill(by_label("Password"), "wrong password!")
      |> click(by_role(:button, name: "Sign in"))
      |> assert(contain_text(by_css("#login-error"), "do not match"))
      |> fill(by_label("Password"), valid_password())
      |> click(by_role(:button, name: "Sign in"))
      |> assert(contain_text(by_css("#crumb"), "Entries"))
    end
  end

  describe "the admin area" do
    test "the wordmark menu opens with sections and presence", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_css("#wmBtn"))
      |> assert(contain_text(by_css("#navMenu"), "New entry"))
      |> assert(contain_text(by_css("#navMenu"), "Here now"))
      |> assert(contain_text(by_css("#navMenu"), "No one else right now."))
      |> assert(contain_text(by_css("#wmMe"), "kb"))
    end
  end

  describe "profile" do
    test "edits save instantly and follow into the menu", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_css("#wmBtn"))
      # the menu opens in the browser: wait for it, or the next click
      # races the script on a slow machine
      |> assert(contain_text(by_css("#navMenu"), "Your profile"))
      |> click(by_role(:link, name: "Your profile"))
      |> assert_has(by_css("#barMe[aria-current=page]"))
      |> assert(contain_text(by_css("#sessions"), "This browser"))
      |> refute_has(by_css("#sessions") |> filter(has_text: "Another browser"))
      |> fill(by_label("Display name"), "Klaus")
      |> assert(contain_text(by_css("#barMe"), "Klaus"))
      |> click(by_css("#wmBtn"))
      |> assert(contain_text(by_css("#wmMe"), "Klaus"))
    end
  end
end
